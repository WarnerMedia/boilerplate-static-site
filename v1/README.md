# Static CDN/Website Deployment (v1)

This is a simple deployment flow for a static S3 website using CloudFront and WAF.

## Table of Contents

- [Overview](#overview)
- [Folder Structure](#folder-structure)
- [Install/Initial Setup](#installinitial-setup)
- [GitHub Branch Flow](#github-branch-flow)
- [AWS CodePipeline Infrastructure](#aws-codepipeline-infrastructure)
- [TODO List](#todo-list)

---
**NOTE**

This repository should never be used directly, the "Use this template" button should always be utilized to create fork of this repository.

---

# Overview

This project has the following features:

1. S3 is used as the static site origin.
    * There is a bucket in the primary region which is where all files are managed.
    * All changes to the primary bucket are replicated to a bucket in the secondary region.
    * Both buckets are used as origins, so if a bucket goes out in one region, the CDN can still serve from the other bucket.
    * The buckets user versioning, so if a file is mistakely deleted, it can be retrieved (by default, for 32 days after deletion).
    * The bucket uses Amazon S3-Managed Keys (SSE-S3) to encrypt all objects (KMS is now allowed when serving from CloudFront).
    * The S3 buckets are not public and use an Origin Access Identity and IAM permissions to get access to the objects in the bucket.
2. IAM users for bucket access are implemented.
    * The first IAM user is designated for general upload use, such as uploading files from another tool or manually.
    * The second IAM user is designated for use by an external CDN (such as Akamai).  It has write permissions in case the external CDN needs to write anything to the S3 bucket.
3. CloudFront distribution for hosting the S3 files.
    * This distribution uses an origin group.  If file requests fail to the primary bucket, CloudFront will request it from the secondary bucket.
    * The distribution has a custom error configuration to reduce the chance of cache poisoning.
    * The distribution uses an Origin Access Identity to communicate with the S3 buckets.
    * The distribution is protected by a Web Application Firewall (WAF).
    * A custom domain can be added to the CloudFront distribution.
4. Web Application Firewall (AWS WAFv2) for protection of the CloudFront distribution and origins.
    * The WAF uses managed rules from AWS meant to protect a general website.
    * The WAF is what can be used to lock down the website to specific CIDR blocks (such as locking down to a VPN).
5. A CodePipeline is used to deploy files from the `content` folder.
    * For any files that need to be managed via git and distributed automatically, they need to go into the main `content` folder.
    * Any files distributed via the CodePipeline will get a default `Cache-Control` header for all files deployed.
    * This distribution process will not do anything destructive, so it will only add and update files.  Deletion of files must be done manually.

## Caveats

1. There is currently no authentication support (only the option to lock behind specific CIDR blocks, such as a VPN CIDR block range).
2. There is currently no way to implement a redirect.
3. There is no way to automatically resize images.
4. Browser "Cache-Control" headers must be set for each file (the deployment process handles this, but doesn't cover manually-uploaded files).

**NOTE:** Some of these features will be added over time.

# Folder Structure

## Current Version Folder

This section describes the layout of the `v1` version of this project.

- [`build`](build): Everything that build processes would need to execute successfully.
    * For AWS CodeBuild, the needed BuildSpec and related shell scripts are all in this folder.
- [`env`](env): Any environment-related override files.
    * There are some JSON files in this folder which are used to override parameters in the CloudFormation templates (via CodePipeline CloudFormation stages).
    * For this project, these will rarely get used, but are here for completeness.
    * This folder could also contain other environment configuration files for the application itself.
- [`iac`](iac): Any infrastructure-as-code (IaC) templates.
    * Currently this only contains CloudFormation YAML templates.
    * The templates are categorized by AWS service to try to make finding and updated infrastructure easy.
    * This folder could also contain templates for other IaC solutions.
- [`test`](test): Any resources needed for doing testing of the application.
    * This project supports [Cucumber.js](https://cucumber.io/docs/installation/javascript/) Behavior-Driven Development (BDD) testing by default.
    * Cucumber.js is a very versatile testing solution which integrates well with CodeBuild reporting.
    * Cucumber tests can be written in [many different programming languages](https://cucumber.io/docs/installation/) including Java, Node.js, Ruby, C++, Go, PHP, Python, etc.
- [`version root`](./): All of the files that are generally designed to be at the base of the project.
    * Miscellaneous files, such as the `README.md` file.

## Root Folder

This section has information on any important files or folders from the root/base folder of this project.

-  [`content`](../content): This folder contains content for the S3 folder.
    * If there is content that needs to always be part of your site, such as a robots.txt file, 404 page, etc.  It can be placed in this folder and will get distributed.
    * In some cases, all content should be managed in the repository so that it can be properly maintained and versioned.
    * In other cases, only key files need to be maintained in the repository and other files may be uploaded manually (such as large content files which are not practical to maintain in git).
    * Please reference the [content README.md](../content/README.md) file for more details.

# Install/Initial Setup

---
**NOTE**

These setup instructions assume that you have already set up the base infrastructure: [boilerplate-aws-account-setup](https://github.com/warnermedia/boilerplate-aws-account-setup)

The `boilerplate-aws-account-setup` repository will get cloned (uisng the "Use this template" button) for each set of the accounts; this allows for base infrastructure changes that are specific to that account.  The changes can be made without impacting the original boilerplate repository.

---

## Prerequisite Setup

### GitHub User Connection

1. This repository is meant to be used as a starting template, so please make use of the "Use this template" button in the GitHub console to create your own copy of this repository.
2. Since you have the base infrastructure in place, in your primary region, there should be an SSM parameter named: `/account/main/github/service/username`
3. This should be the name of the GitHub service account that was created for use with your AWS account.
4. You will want to add this service account user to your new repository (since the repository is likely private, this is required).
5. During the initial setup, the GitHub service account will need to be given admin. access so that it can create the needed webhook (no other access level can create webhooks at this time).
6. Once you try to add the service account user to your repository, someone who is on the mailing list for that service account should approve the request.

---
**NOTE**

You will need either DevOps or Admin SSO role in order to have enough permissions to set things up.

---

## Primary Setup

1. Switch to the `v1` folder.
2. Find the following CloudFormation template: [`iac/cfn/setup/main.yaml`](iac/cfn/setup/main.yaml)
3. Log into the AWS Console for your account.
4. Go to the CloudFormation console.
5. Upload this template and then fill in all of the needed parameter values.
     - The first parameter in this template has a suggested stack name in it, you will want to copy this value and modify it to a stack name that makes sense for your project.  You will then want to put this in the "Stack name" field.
     - Make sure that all of the parameters in the "Source Configuration" parameter group match with your new repository and are not pointing back to the original boilerplate repository.
6. Go through all the other CloudFormation screens and then launch the stack.
7. Monitor the stack and make sure that it completes successfully.
8. This will have created an orchestrator CodeBuild and setup CodePipeline.  The orchestrator CodeBuild will need to be triggered either manually or via a change to the GitHub repository. 

---
**NOTE**

You would run the above "Primary Setup" for each environment that you want to establish.

Typically, you would probably only set up a non-prod and prod instance, you can use S3 subfolders to separate out content, if needed.

---

# GitHub Branch Flow

---
**NOTE**

Use of direct commits to the `main` branch is discouraged.  Pull requests should always be used to help give visibility to all changes that are being made.

---

## Development Flow

This repository uses a trunk-based development flow.  You can read up on trunk-based flows on this website:

[https://trunkbaseddevelopment.com](https://trunkbaseddevelopment.com)

## Commenting of Commits

The use of "Conventional Commits" is encouraged in order to help make commit message more meaningful. Details can be found on the following website:

[https://www.conventionalcommits.org](https://www.conventionalcommits.org)

## Primary Branches

1. `main`:
    - This branch is the primary branch that all bug and feature branches will be created from and merged into.
    - For the purposes of this flow, it is the "trunk" branch.
2. `feature`/`bugfix` branches:
    - These branches will be created from the `main` branch.
    - Engineers will use their `feature`/`bugfix` branch for local development.
    - Feature branch names typically take the form of `f/(ticket number)/(short description)`.  For example, `f/ABC-123/update-service-resources`
    - Bug fix branch names typically take the form of `b/(ticket number)/(short description)`.  For example, `b/ABC-123/correct-service-variable`
    - Once a change is deemed ready locally, a pull request should be used to get it merged into the `main` branch.
    - All `feature`/`bugfix` branches should be considered temporary and can be deleted once merged into the `main` branch.  The pull request will keep the details of what was merged.

## General Flow

### Local Development

1. An engineer would create a `feature`/`bugfix` branch from the local checkout of the local, current `main` branch.
2. The engineer would then make their content or infrastructure changes and additions.
3. Once things look good locally, the engineer would push the branch to GitHub.

### Update Deployment

1. In GitHub, a pull request will be created to the `main` branch using the `feature`/`bugfix` branch.
2. If there are critical content or any infrastructure changes, a peer review should be done of the pull request by at least one other engineer.
3. Once the pull request is approved, it will be merged into the `main` branch.
4. If there are content changes, the content deployment CodePipeline will be triggered once the CodeBuild orchestrator completes.
5. If there are infrastructure changes, the setup and infrastructure CodePipelines may both be triggered (depending on what was all changed).  These will be triggered once the CodeBuild orchestrator completes.

# AWS CodePipeline Infrastructure

This project uses AWS CodePipeline to get your site infrastructure deployed.  Here are some details:

- There is a single CodePipeline which will allow you to deploy a testing and production version of the Lambda function.
- The CodePipeline is triggered by a GitHub webhook which is created when the CodePipeline is first created by CloudFormation.
- The CodePipeline has a manual approval step after the testing version has been deployed.
- If the manual approval is rejected, then the CodePipeline stops and does not deploy the function to production.
- If the manual approval is approved, then the CodePipeline will deploy the latest code to the production version of the Lambda.
    * **NOTE:** If CodePipelines for this project are set up in multiple accounts or regions, they each need to be individually approved. -->

# AWS CodeBuild/CodePipeline Infrastructure

This project uses AWS CodeBuild and AWS CodePipeline to get your static site deployed.  Here we will outline the different components of the deployment flow.

## CodeBuild Orchestrator

- The orchestrator is a CodeBuild project which is triggered by a GitHub Webhook.
- This CodeBuild project can be found in the primary region where you set up the infrastructure and have a name that follows this pattern: `(your project name)-orchestrator`
- The orchestrator will examine the changes that were just committed and determine the type of change which was just made.
- The changes will be packaged into different ZIP archives and then deploy them to archive S3 bucket.
- The appropriate CodePipelines will then be triggered based on the type of change that was committed.
- The orchestrator creates different ZIP archives, the contents of those ZIP archives are managed by `*.list` files which are located here: [`env/cfn/codebuild/orchestrator/`](env/cfn/codebuild/orchestrator/)

## Project Infrastructure CodePipelines

- There are two project infrastructure CodePipelines, the setup CodePipeline and the Infrastructure CodePipeline.

### Setup CodePipeline

- When the initial setup CloudFormation template runs, it creates a setup CodePipeline.
- This CodePipeline will get triggered within a minute of the first successful CodeBuild orchestrator run.
- This CodePipeline is very simple, it's only purpose is to create and maintain the infrastructure CodePipeline.
- This CodePipeline may feel like an extra step, but it is there so that project infrastructure changes can be made easily.
- Updates to the CodePipeline should be rare.
- **NOTE:** If changes need to be made to the setup CodePipeline, then the the [main setup template](iac/cfn/setup/main.yaml) will need to be edited and the changes manually run from the AWS CloudFormation console.

### Infrastructure CodePipeline

- This CodePipeline is initially created and maintained by the setup CodePipeline.
- The template that manages this CodePipeline is located here: [`iac/cfn/codepipeline/infrastructure.yaml`](iac/cfn/codepipeline/infrastructure.yaml)
- Any environment parameters overrides can be set in the JSON files located in this folder: [`env/cfn/codepipeline/infrastructure`](env/cfn/codepipeline/infrastructure)
- This CodePipeline will create/maintain all of the base infrastructure for this project.  Some examples are:
    * S3 Buckets
    * IAM Users
    * CloudFront Distributions
    * WAF Configuration
- You can review the CloudFormation parameters in the [infrastructure CodePipeline](iac/cfn/codepipeline/infrastructure.yaml) template to see what options are all available.
    * For example, there is a parameter to turn on a manual approval step for the infrastructure CodePipeline; this is useful for approving changes to the production infrastructure after being verified in non-prod.
- You would use this CodePipeline to set up things that are shared by all deployment CodePipelines, or things that will rarely change.

## Content Deployment CodePipeline

- There is an individual CodePipeline for deploying content to the primary S3 bucket.
- All files in the [content](../content/) folder will get deployed by this CodePipeline.
- CodePipeline uses a simple deployment feature to get files deployed out to S3. It will not do anything destructive, it will only add or update files in the S3 bucket.
- To get more details about the content deployment, please view the [README.md](../content/README.md) file.

# TODO List

1. Finish up the infrastructure testing stage.  The tests are there, but the testing stage needs to be added to the infrastructure flow.
2. Add Lambda@Edge function which would support Basic Auth.
3. Add Lambda@Edge function which would support image manipulation.
4. Add Lambda@Edge function which would support redirects at the edge?
5. Improve overall documentation.