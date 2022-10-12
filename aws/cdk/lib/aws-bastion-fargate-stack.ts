import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as assets from "aws-cdk-lib/aws-ecr-assets";

export interface AwsBastionFargateStackProps extends cdk.StackProps {
}

export class AwsBastionFargateStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: AwsBastionFargateStackProps) {
    super(scope, id, props);

    const taskExecutionRole = new iam.Role(this, 'EcsTaskExecutionRole', {
      roleName: 'bastion-ecs-task-execution-role',
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy')
      ],
    });

    new iam.Role(this, 'SSMRole', {
      roleName: 'bastion-ssm-role',
      description: 'Allows SSM to call AWS services on your behalf',
      assumedBy: new iam.ServicePrincipal('ssm.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore')
      ]
    });

    const taskRole = new iam.Role(this, 'EcsTaskRole', {
      roleName: 'bastion-ecs-task-role',
      description: 'Allows ECS tasks to call AWS services on your behalf.',
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      inlinePolicies: {
        ['ecs-policy']: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              actions: [
                "ssmmessages:CreateControlChannel",
                "ssmmessages:CreateDataChannel",
                "ssmmessages:OpenControlChannel",
                "ssmmessages:OpenDataChannel"
              ],
              resources: [
                '*'
              ],
            }),
          ]
        }),
        ['log-output-policy']: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              actions: [
                "logs:DescribeLogGroups",
                "logs:CreateLogStream",
                "logs:DescribeLogStreams",
                "logs:PutLogEvents"
              ],
              resources: [
                '*'
              ]
            })
          ]
        })
      }
    });

    // 👇ECSタスク定義
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'TaskDefinition', {
      family: 'bastion-task-def',
      cpu: 256,
      memoryLimitMiB: 512,
      executionRole: taskExecutionRole,
      taskRole: taskRole,

    });
    // 👇Bastionコンテナ定義
    taskDefinition.addContainer('BastionTaskContainerDefinition', {
      containerName: 'bastion-container',
      image: ecs.ContainerImage.fromDockerImageAsset(new assets.DockerImageAsset(this, 'BastionBuildImage', {
        directory: '../../docker/',
        file: 'Dockerfile',
      })),
      essential: true,
      linuxParameters: new ecs.LinuxParameters(this, 'LinuxParams', {
        initProcessEnabled: true
      }),
      logging: ecs.LogDriver.awsLogs({
        streamPrefix: 'logs',
        logGroup: new logs.LogGroup(this, 'ECSBastionContainerLogGroup', {
          logGroupName: '/my/ecs/container/bastion'
        }),
      }),
    });
  }
}
