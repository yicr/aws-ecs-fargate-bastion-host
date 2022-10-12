#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { AwsBastionFargateStack } from '../lib/aws-bastion-fargate-stack';

const app = new cdk.App();
new AwsBastionFargateStack(app, 'AwsBastionFargateStack', {
  stackName: 'aws-bastion-fargate-stack',
  env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: 'ap-northeast-1' },
});