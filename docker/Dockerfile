FROM public.ecr.aws/amazonlinux/amazonlinux:2

RUN yum install -y sudo git jq awscli shadow-utils htop lsof telnet bind-utils yum-utils
#    adduser ssm-user && echo "ssm-user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ssm-agent-users && \
#    mv /etc/amazon/ssm/amazon-ssm-agent.json.template /etc/amazon/ssm/amazon-ssm-agent.json && \
#    mv /etc/amazon/ssm/seelog.xml.template /etc/amazon/ssm/seelog.xml
COPY asset/MariaDB.repo /etc/yum.repos.d/MariaDB.repo
RUN yum install -y MariaDB-client

RUN curl -fsSL https://rpm.nodesource.com/setup_16.x | bash && \
      yum install -y nodejs
#COPY task.sh /task.sh
#CMD ["sh", "/task.sh"]

# 12H
CMD ["sleep", "43200"]
