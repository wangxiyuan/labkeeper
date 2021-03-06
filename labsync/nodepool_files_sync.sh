#!/bin/bash -ex
# Copyright 2015 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

github_username=$1
github_useremail=$2
github_token=$3
deploy_type=${4:-openlab}

local_clouds_file=/etc/openstack/clouds.yaml
local_nodepool_file=/etc/nodepool/nodepool.yaml
nodepool_file=~/inotify/labkeeper/etc/nodepool/${deploy_type}-nodepool.yaml.j2
clouds_file=~/inotify/labkeeper/etc/nodepool/${deploy_type}-clouds.yaml.j2
secrets_file=~/inotify/labkeeper/etc/nodepool/clouds-secrets.yaml

set -e

# the default path of cron is /usr/bin:/bin, add hub path to PATH
export PATH=/usr/local/bin:$PATH

bash /home/ubuntu/sync_prepare.sh ${github_username} ${github_useremail} ${github_token}

cd ~/inotify/labkeeper/
hub checkout master
hub pull
modify_time=`date +%Y%m%d%H%M`
branch_name="update${modify_time}"
message="[Nodepool_Sync] Sync_${modify_time}_modified_by_${github_username}"
hub remote update
# sync update for forked repo
hub merge upstream/master
hub push origin
# checkout a new branch based on upstream
hub checkout -b ${branch_name} upstream/master

# update files
cp /home/ubuntu/vault-password.txt vault-password.txt
cp $local_nodepool_file  nodepool_temp.yaml
cp $local_clouds_file clouds_temp.yaml
cp $secrets_file secrets_temp.yaml

# decrypt the secrets in clouds-secrets.yaml
for key in `cat $secrets_file | shyaml keys`
do
    echo "$key: `cat  $secrets_file | shyaml get-value $key | ansible-vault decrypt`" >> old_secrets_decrypted.yaml
done

do_clean_up()
{
  ERROR_CODE="$?"
  echo "Cleaning up temporary files before exiting, the exit code is ${ERROR_CODE}..."
  rm -f old_secrets_decrypted.yaml vault-password.txt nodepool_temp.yaml secrets_temp.yaml clouds_temp.yaml
  hub checkout master
  hub branch -D ${branch_name}
  echo "Cleaning up done."
  exit ${ERROR_CODE}
}
trap "do_clean_up" EXIT

python /home/ubuntu/modify_files.py

# delete the lines from 'labels:' to end for template
sed -i '/^labels/,$d' $nodepool_file
# copy the lines from 'labels' to end to template
sed -n '/^labels/,$p' nodepool_temp.yaml >> $nodepool_file

mv clouds_temp.yaml $clouds_file
mv secrets_temp.yaml $secrets_file

if [[ `hub status |grep modified` ]];then
    hub add $clouds_file
    hub add $secrets_file
    hub add $nodepool_file
    hub commit -m "${message}"
    hub push origin ${branch_name}

    # using hub to create pull-request
    ## avoid being prompted username and password when execute cmd 'hub pull-request'
    export GITHUB_TOKEN=${github_token}
    hub pull-request -m "${message}"
    echo "Create pull request to theopenlab/labkeeper success!"
fi
