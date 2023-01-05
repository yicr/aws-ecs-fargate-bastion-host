#!/bin/bash
set -eu

# コマンド有無確認
if ! type "aws" > /dev/null 2>&1; then
    echo "aws command not installed."
    exit 1
fi

if ! type "jq" > /dev/null 2>&1; then
    echo "jq command not installed."
    exit 1
fi

if [ ! -e .env ]; then
  echo ".env not found."
  exit 1
fi

myIdentity=$(aws sts get-caller-identity)
echo -e "Account: $(echo $myIdentity | jq -r '.Account')"
echo -e "UserId: $(echo $myIdentity | jq -r '.UserId')"

echo -e ""
read -p "Is it alright? [Y/n]: " ANS
case $ANS in
  [Yy]* )
    echo -e "process continue..."
    ;;
  * )
    echo -e "process exit."
    exit 0
    ;;
esac

source .env

fargateClusterName=$FARGATE_CLUSTER_NAME
taskDefinitionName=$TASK_DEFINITION_NAME

# 引数の数確認
#if [ $# -ne 1 ]; then
#  echo -e "Error: invalid argument (1).";
#  echo -e "Usage: $0 <aws-stage-name>";
#  echo -e "<aws-stage-name> : prd / stg / dev";
#  exit 1
#else
#  if ! [[ "$1" = "dev" || "$1" = "stg" || "$1" = "prd" ]]; then
#    echo -e "Error: invalid argument (2).";
#    echo -e "Usage: $0 <aws-stage-name>";
#    echo -e "<aws-stage-name> : prd / stg / dev";
#    exit 1
#  fi
#fi

# 指定したタスク定義で起動しているタスクを取得する
function getRunningTaskArn() {
  aws ecs list-tasks \
    --cluster $fargateClusterName \
    --family $taskDefinitionName \
    --desired-status RUNNING \
    --region ap-northeast-1 \
    | jq '.taskArns[0]' \
    | tr '\n' ',' \
    | sed -e 's/,$/\n/g' \
    | sed 's/"//g'
}

# Get private subnet ids
function getPrivateSubnets() {
  aws ec2 describe-subnets \
    --filters "Name=tag:aws-cdk:subnet-name,Values=Private" \
    --region ap-northeast-1 \
    | jq '.Subnets[].SubnetId' \
    | tr '\n' ',' \
    | sed -e 's/,$/\n/g' \
    | sed 's/"//g'
}

# Get security group
function getBastionSecurityGroups() {
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=batch-task-sg" \
    --region ap-northeast-1 \
    | jq '.SecurityGroups[].GroupId' \
    | tr '\n' ',' \
    | sed -e 's/,$/\n/g' \
    | sed 's/"//g'
}

function doWaitRunningTask() {
  if [[ $# -eq 1 ]]; then
    local taskArn=$1

    aws ecs wait tasks-running \
      --tasks ${taskArn} \
      --cluster "${fargateClusterName}" \
      --region ap-northeast-1
  else
    echo -e "Error: wait running-task."
    exit 1
  fi
}

# Do run task
function doRunTask() {
  if [[ $# -eq 2 ]]; then
    local subnets=$1
    local securityGroups=$2

    # タスク開始
    local taskArn
    taskArn=$(aws ecs run-task \
      --task-definition ${taskDefinitionName} \
      --cluster "${fargateClusterName}" \
      --region ap-northeast-1 \
      --launch-type FARGATE \
      --count 1 \
      --enable-execute-command \
      --network-configuration "awsvpcConfiguration={subnets=[${subnets}],securityGroups=[${securityGroups}],assignPublicIp=DISABLED}" \
      --query "tasks[0].taskArn" \
      --output text)
    echo $taskArn
  else
    echo -e "Error: run-task."
    exit 1
  fi
}

function doExecLoginContainer() {
  local taskArn=$1
  aws ecs execute-command --cluster "${fargateClusterName}" \
    --region ap-northeast-1 \
    --task ${taskArn} \
    --container bastion-container \
    --interactive \
    --command "/bin/bash"
}

function doStopTask() {
  local taskArn=$1
  aws ecs stop-task \
    --task $taskArn \
    --cluster "${fargateClusterName}" \
    --region ap-northeast-1 \
    --query "task.taskDefinitionArn" \
    --output text
}

function doWaitStopTask() {
  local taskArn=$1
  aws ecs wait tasks-stopped \
    --tasks ${taskArn} \
    --cluster $fargateClusterName \
    --region ap-northeast-1
}

case "${1:-}" in
  # 開始＆ログイン
  start)
    echo -e task start
    # check family=bastion-task-def already running
    runningTaskArn=`getRunningTaskArn`

    # when running task.
    if [[ -n $runningTaskArn && $runningTaskArn != null ]]; then
      echo -e "Already running task."
      echo -e "TaskArn: ${runningTaskArn}"
      read -p "Login running task container? (ECSExec) [Y/n]: " ANS
      # exit when already running task.
      case $ANS in
        [Yy]* )
          echo -e "login task container..."
          doExecLoginContainer $runningTaskArn
          ;;
        * )
          echo -e "process exit."
          ;;
      esac
      exit 0
    fi

    # get subnet ids
    targetSubnets=`getPrivateSubnets`
    if [[ -n $targetSubnets ]]; then
      echo -e "Subnets:"
      echo -e "  ${targetSubnets}"
    fi

    # get security group ids
    targetSecurityGroups=`getBastionSecurityGroups`
    if [[ -n $targetSecurityGroups ]]; then
      echo -e "SecurityGroups:"
      echo -e "  ${targetSecurityGroups}"
    fi

    # do run-task
    echo -e "run task..."
    taskArn=`doRunTask $targetSubnets $targetSecurityGroups`
    echo -e "TaskArn: "
    echo -e "  ${taskArn}"

    read -p "Login running task? (ECSExec) [Y/n]: " ANS
    echo -e ""
    case $ANS in
      [Yy]* )
        echo -e "Yes"
        echo -e "please waiting task running..."
        doWaitRunningTask $taskArn
        echo -e "login task container..."
        doExecLoginContainer $taskArn
        ;;
      * )
        echo -e "process exit."
        ;;
    esac

    exit 0
  ;;

  stop)
    echo -e task stop

    runningTaskArn=`getRunningTaskArn`

    if [[ -n $runningTaskArn ]]; then
      echo -e "TaskArn: ${runningTaskArn}"
      echo -e "stop task..."

      taskDefinitionArn=`doStopTask $runningTaskArn`

      echo -e "TaskDefinitionArn : ${taskDefinitionArn}"

      doWaitStopTask taskDefinitionArn

      echo -e "stop task finished."
    else
      echo -e "bastion task not started."
    fi
    exit 0
  ;;

  *)
    echo "[ERROR] Invalid subcommand '${1:-}'"
    #usage
    exit 1
    ;;
esac
