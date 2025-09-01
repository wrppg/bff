#!/usr/bin/env bash
pwd
curl -o yq -L https://github.com/mikefarah/yq/releases/download/v4.47.1/yq_linux_amd64
./yq --version

# mkdir "$HOME"/bin
# echo "$HOME"/bin >> $GITHUB_PATH
# yq --version
