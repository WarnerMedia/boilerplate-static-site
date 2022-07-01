# Content Folder

1. Your static site content goes in this folder.
2. Anything in this folder will get automatically deployed to a "content" folder in your primary S3 bucket.
    * This allows you to put some files in your S3 bucket which will not be available to CloudFront.
3. By default, the CloudFront distribution uses "/content" as the origin path, so content from this folder will be at the root level of your CloudFront distribution.
4. The CodePipeline that deploys content from this folder also sets a default Cache-Control header for all objects.  You can configure this in CloudFormation.
5. The method used to distribute the contents of this folder only adds and updates, it doesn't do anything destructive.  Because of this, obsolete files need to be removed manually.
6. This `README.md` file is excluded from the content distribution.