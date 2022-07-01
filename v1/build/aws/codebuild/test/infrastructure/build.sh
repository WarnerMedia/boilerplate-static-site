#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

echo "Build Started on $(date)"

#------------------------------------------------------------------------
# BEGIN: Main Logic
#------------------------------------------------------------------------

if [ -n "$APP_BASE_FOLDER" ]; then
  cd "$CODEBUILD_SRC_DIR/$APP_BASE_FOLDER/$TEST_BASE_PATH" || exit 1;
else
  cd "$CODEBUILD_SRC_DIR/$TEST_BASE_PATH" || exit 1;
fi

echo "Run the infrastructure tests..."
npm run test-infrastructure

#------------------------------------------------------------------------
# END: Main Logic
#------------------------------------------------------------------------