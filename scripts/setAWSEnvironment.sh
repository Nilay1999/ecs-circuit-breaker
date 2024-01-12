#!/usr/bin/env sh
echo '*********************************************'
echo 'creating ~/.aws'
mkdir -p ~/.aws
printf "[wickes-sls]\naws_access_key_id=\"$AWS_KEY\"\naws_secret_access_key=\"$AWS_SECRET\"\n[wickes-sls-test]\nrole_arn=arn:aws:iam::350245524826:role/sts_account_admin\nsource_profile=wickes-sls" > ~/.aws/credentials
echo '*********************************************'