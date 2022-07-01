#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

#------------------------------------------------------------------------
# BEGIN: Set some default variables and files
#------------------------------------------------------------------------

#Global variables.
BASE_LIST_PATH="env/cfn/codebuild/orchestrator/"
COMPARE_FOLDER="compare"
INSTALL_COMMAND="npm install --only=prod"
OUTPUT_FILE_FOLDER="tmp"
ZIP_FOLDER="archive"

#Replace the install command if a custom command has been passed in.
if [ -n "$CUSTOM_INSTALL_COMMAND" ]; then
  echo "Custom install command has been set..."
  INSTALL_COMMAND="$CUSTOM_INSTALL_COMMAND"
  echo "Install command is now \"$INSTALL_COMMAND\"..."
fi

#Get the soure file base (sans extension)
IAC_FILE_BASE=$(echo "$IAC_ZIP_FILE" | rev | cut -d. -f2- | rev)
CONTENT_FILE_BASE=$(echo "$CONTENT_ZIP_FILE" | rev | cut -d. -f2- | rev)
TEST_FILE_BASE=$(echo "$TEST_ZIP_FILE" | rev | cut -d. -f2- | rev)
SETUP_FILE_BASE=$(echo "$SETUP_ZIP_FILE" | rev | cut -d. -f2- | rev)

#Lists of files to include.
IAC_INCLUDE_LIST="$BASE_LIST_PATH${IAC_FILE_BASE}_include.list"
CONTENT_INCLUDE_LIST="$BASE_LIST_PATH${CONTENT_FILE_BASE}_include.list"
TEST_INCLUDE_LIST="$BASE_LIST_PATH${TEST_FILE_BASE}_include.list"
SETUP_INCLUDE_LIST="$BASE_LIST_PATH${SETUP_FILE_BASE}_include.list"

#Lists of files to exclude.
IAC_EXCLUDE_LIST="$BASE_LIST_PATH${IAC_FILE_BASE}_exclude.list"
CONTENT_EXCLUDE_LIST="$BASE_LIST_PATH${CONTENT_FILE_BASE}_exclude.list"
TEST_EXCLUDE_LIST="$BASE_LIST_PATH${TEST_FILE_BASE}_exclude.list"
SETUP_EXCLUDE_LIST="$BASE_LIST_PATH${SETUP_FILE_BASE}_exclude.list"

#------------------------------------------------------------------------
# END: Set some default variables and files
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Declare some functions
#------------------------------------------------------------------------

check_cmd_exists () {

  local cmd="$1"
  local version_check="$2"

  echo "Check if the \"$cmd\" command is installed..."
  if exists "$cmd"; then
    echo "The command \"$cmd\" is installed..."
    echo "Check the version..."
    eval "$cmd $version_check"
  else
    echo "The \"$cmd\" command is not installed.  Please install this command."
    exit 1
  fi

}

#Check if we need to install the NPM modules.
check_execute_install_command () {

  if [ "$ENABLE_DEP_INSTALL" = "Yes" ]; then

    # If there is an application base folder, switch to it...
    if [ -n "$APP_BASE_FOLDER" ]; then
      cd "$CODEBUILD_SRC_DIR/$APP_BASE_FOLDER" || exit 1;
    fi

    echo "Running \"$INSTALL_COMMAND\" command..."
    eval "$INSTALL_COMMAND"

    echo "Do a directory listing..."
    ls -altr

    # If there is an application base folder, switch back to the original base folder...
    if [ -n "$APP_BASE_FOLDER" ]; then
      cd "$CODEBUILD_SRC_DIR" || exit 1;
    fi

  else

    echo "Not running \"$INSTALL_COMMAND\" command..."

  fi

}

#Check if the AWS command was successful.
check_status () {
  #The $? variable always contains the status code of the previously run command.
  #We can either pass in $? or this function will use it as the default value if nothing is passed in.
  local prev=${1:-$?}
  local command="$2"

  if [ $prev -eq 0 ]; then
    echo "The $command command has succeeded."
  else
    echo "The $command command has failed."
    exit 1
  fi
}

#The following function is used when an option has a value.
check_option () {
  local key="$1"
  local value="$2"

  #Check if we have an empty value.
  if [ -z "$value" ] || [ "$(echo "$value" | cut -c1-1)" = "-" ]; then
    echo "Error: Missing value for argument \"$key\"."
    exit 64
  fi

  #Since none of the above conditions were met, we assume we have a valid value.
  SHIFT_COUNT=2
  return 0
}

#Compare two zip files...
#NOTE: zipcmp must be used for the comparison because zip creation metadata will change MD5 hashes.
compare_zip_file () {

  local zip_filename="$1"
  local codepipeline="$2"
  local pushfile="false"
  local status="fail"

  echo "Try to get \"$zip_filename\" compare ZIP file from S3..."
  aws s3 cp "s3://$S3_BUCKET/$S3_FOLDER/compare/$zip_filename" "/$OUTPUT_FILE_FOLDER/$COMPARE_FOLDER/$zip_filename" --region "$AWS_REGION"

  #Doing a comparison to see if we should push the new ZIP file or not.
  echo "Checking if ZIP file \"$zip_filename\" exists on S3..."
  if [ -e "/$OUTPUT_FILE_FOLDER/$COMPARE_FOLDER/$zip_filename" ]; then

    #Check if there is a difference between ZIP files.
    echo "Doing zipcmp compare..."
    zipcmp "/$OUTPUT_FILE_FOLDER/$ZIP_FOLDER/$zip_filename" "/$OUTPUT_FILE_FOLDER/$COMPARE_FOLDER/$zip_filename"

    #If the exit code was 1, then we know there were changes to the ZIP file and it should be uploaded.
    if [ $? -eq 1 ]; then
      echo "Changes to ZIP file \"$zip_filename\"...will push to S3."
      pushfile="true"
    else
      echo "No changes to ZIP file \"$zip_filename\"...will not push ZIP file."
    fi
  else
    echo "ZIP file \"$zip_filename\" doesn't exist on S3...will push to S3."
    pushfile="true"
  fi

  #Push the file if the flag was set to "true" at some point in this run through the loop.
  if [ "$pushfile" = "true" ]; then

    status=$(push_file "/$OUTPUT_FILE_FOLDER/$ZIP_FOLDER/$zip_filename" "s3://$S3_BUCKET/$S3_FOLDER/compare/$zip_filename")

    echo "Current status is: $status"

    if [ "$status" = "success" ]; then
      echo "Successfully pushed compare file to S3."

      status=$(push_file "/$OUTPUT_FILE_FOLDER/$ZIP_FOLDER/$zip_filename" "s3://$S3_BUCKET/$S3_FOLDER/base/$zip_filename")

      if [ "$status" = "success" ]; then
        echo "Successfully pushed deployment file to S3."
        start_codepipeline "$codepipeline"
      else
        echo "Failed to push deployment file to S3."
        exit 1
      fi
    else
      echo "Failed to push compare file to S3."
      exit 1
    fi
  fi
}

#Create a ZIP archive file...
create_compare_zip () {
  local zip_folder="$1"
  local zip_filename="$2"
  local exclude_list="$3"
  local include_list="$4"

  if [ -n "$APP_BASE_FOLDER" ]; then
    exclude_list="$APP_BASE_FOLDER/$exclude_list"
    include_list="$APP_BASE_FOLDER/$include_list"
  fi

  echo "Zipping up files for the \"$zip_filename\" archive..."
  mkdir -p "/$OUTPUT_FILE_FOLDER/$zip_folder"
  zip -X -r "/$OUTPUT_FILE_FOLDER/$zip_folder/$zip_filename" -x@"$exclude_list" . -i@"$include_list"
}

#Check if required commands exist...
exists () {
  command -v "$1" >/dev/null 2>&1
}

push_file () {
  local source="$1"
  local destination="$2"

  aws s3 cp "$source" "$destination" --region "$AWS_REGION" --quiet
  if [ $? -ne 0 ]; then
    echo "fail"
  else
    echo "success"
  fi
}

push_regular_environment () {

  echo "Creating the various ZIP files..."

  #Create Setup ZIP file.
  create_compare_zip "$ZIP_FOLDER" "$SETUP_ZIP_FILE" "$SETUP_EXCLUDE_LIST" "$SETUP_INCLUDE_LIST"

  #Create IaC ZIP file.
  create_compare_zip "$ZIP_FOLDER" "$IAC_ZIP_FILE" "$IAC_EXCLUDE_LIST" "$IAC_INCLUDE_LIST"

  #Create Content ZIP file.
  create_compare_zip "$ZIP_FOLDER" "$CONTENT_ZIP_FILE" "$CONTENT_EXCLUDE_LIST" "$CONTENT_INCLUDE_LIST"

  #Create Test ZIP file.
  #create_compare_zip "$ZIP_FOLDER" "$TEST_ZIP_FILE" "$TEST_EXCLUDE_LIST" "$TEST_INCLUDE_LIST"

  echo "Comparing the various ZIP files..."

  #Check setup ZIP file.
  compare_zip_file "$SETUP_ZIP_FILE" "$SETUP_CODEPIPELINE"

  #Check Test ZIP file.
  #compare_zip_file "$TEST_ZIP_FILE" "NONE"

  #Check Content ZIP file.
  compare_zip_file "$CONTENT_ZIP_FILE" "$DEPLOY_CODEPIPELINE"

  #Check IaC ZIP file.
  compare_zip_file "$IAC_ZIP_FILE" "$IAC_CODEPIPELINE"

}

#Because of how CodeBuild does the checkout from GitHub, we have to get creative as to how to get the correct branch name.
retrieve_github_branch () {
  local branch=""
  local trigger="none"

  if [ -n "$CODEBUILD_WEBHOOK_TRIGGER" ]; then
    case "$(echo "$CODEBUILD_WEBHOOK_TRIGGER" | cut -c1-2)" in
      "br") trigger="branch" ; branch=$(echo "$CODEBUILD_WEBHOOK_TRIGGER" | cut -c8-) ;;
      "pr") trigger="pull-request" ;;
      "ta") trigger="tag" ;;
      *) trigger="unknown" ;;
    esac
  fi

  if [ "$trigger" = "branch" ]; then
    #This came from a branch trigger, so output the branch name we parsed.
    echo "$branch"
  elif [ -n "$CODEBUILD_SOURCE_VERSION" ]; then
    #This CodeBuild was triggered directly, most-likely using a branch.
    echo "$CODEBUILD_SOURCE_VERSION"
  else
    #If all else fails, try to get the branch name from git directly.
    git name-rev --name-only HEAD
  fi
}

retrieve_github_organization () {
  local remote="$1"

  if [ "$(echo "$remote" | cut -c1-15)" = "git@github.com:" ]; then
    echo "$remote" | cut -c16- | cut -d/ -f1
  elif [ "$(echo "$remote" | cut -c1-19)" = "https://github.com/" ]; then
    echo "$remote" | cut -c20- | cut -d/ -f1
  else
    echo "UNKNOWN"
  fi
}

retrieve_github_repository () {
  local remote="$1"

  if [ "$(echo "$remote" | cut -c1-15)" = "git@github.com:" ]; then
    echo "$remote" | cut -c16- | rev | cut -c5- | rev | cut -d/ -f2-
  elif [ "$(echo "$remote" | cut -c1-19)" = "https://github.com/" ]; then
    echo "$remote" | cut -c20- | rev | cut -c5- | rev | cut -d/ -f2-
  else
    echo "UNKNOWN"
  fi
}

start_codepipeline () {
  local name="$1"
  local query="pipelines[?contains(name, \`$name\`)].name"
  local compare=""

  echo "Check if the \"$name\" CodePipeline exists..."

  compare=$(aws --region "$AWS_REGION" codepipeline list-pipelines --output text --query "$query")
  check_status $? "AWS CLI"

  if [ "$name" = "$compare" ]; then

    echo "The \"$name\" CodePipeline exists, starting CodePipeline..."

    aws --region "$AWS_REGION" codepipeline start-pipeline-execution --name "$name"
    check_status $? "AWS CLI"

  else

    echo "The \"$name\" CodePipeline doesn't exist in this environment, so nothing to trigger."

  fi
}

#------------------------------------------------------------------------
# END: Declare some functions
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Set Git Variables
#------------------------------------------------------------------------

#Set some git variables...
echo "Retrieve the remote origin URL..."
GIT_REMOTE_URL=$(git config --local remote.origin.url)

echo "Retrieve the full git revision..."
GIT_FULL_REVISION=$(git rev-parse HEAD)
check_status $? "git"

echo "Retrieve the short git revision..."
GIT_SHORT_REVISION=$(git rev-parse --short HEAD)
check_status $? "git"

echo "Retrieve the git branch..."
echo "CODEBUILD_WEBHOOK_TRIGGER: $CODEBUILD_WEBHOOK_TRIGGER"
echo "CODEBUILD_SOURCE_VERSION: $CODEBUILD_SOURCE_VERSION"
GIT_BRANCH=$(retrieve_github_branch)

echo "Retrieve the GitHub organization..."
GITHUB_ORGANIZATION=$(retrieve_github_organization "$GIT_REMOTE_URL")
check_status $? "git"

echo "Retrieve the GitHub repository..."
GITHUB_REPOSITORY=$(retrieve_github_repository "$GIT_REMOTE_URL")
check_status $? "git"

#------------------------------------------------------------------------
# END: Set Git Variables
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Main Build Logic
#------------------------------------------------------------------------

check_cmd_exists "aws" "--version"

check_cmd_exists "jq" "-V"

check_cmd_exists "npm" "-v"

check_cmd_exists "yarn" "-v"

check_cmd_exists "zip" "--version"

check_cmd_exists "zipcmp" "-V"

#Output some variables
echo "Git full revision is: $GIT_FULL_REVISION"
echo "Git short revision is: $GIT_SHORT_REVISION"
echo "Git branch name is: $GIT_BRANCH"
echo "GitHub organization: $GITHUB_ORGANIZATION"
echo "GitHub repository: $GITHUB_REPOSITORY"

echo "Do a directory listing of the base directory..."
ls -altr

#Loop through the arguments.
while [ $# -gt 0 ]; do
  case "$1" in
    # Required Arguments
    -b|--bucket)  check_option "$1" "$2"; S3_BUCKET="$2"; shift $SHIFT_COUNT;;       # S3 bucket ID.
    -f|--folder)  check_option "$1" "$2"; S3_FOLDER="$2"; shift $SHIFT_COUNT;;       # S3 top folder if not deploying to top level of bucket.
    -r|--region)  check_option "$1" "$2"; REGION="$2"; shift $SHIFT_COUNT;;          # AWS region.
    -v|--version) check_option "$1" "$2"; APP_BASE_FOLDER="$2"; shift $SHIFT_COUNT;; # Application Version folder.
    *) echo "Error: Invalid argument \"$1\"" ; exit 64 ;;
  esac
done

#Check if the orchestrator should install the Node.js modules.
check_execute_install_command

#Deploy ZIP files to the primary environment.
push_regular_environment

#------------------------------------------------------------------------
# END: Main Build Logic
#------------------------------------------------------------------------