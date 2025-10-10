profilename="231"
subscription="234"
rg="GR_FrontDoor_WAF"
ep="123"
echo "🚀 Purging your endpont '$ep' ..."


az afd endpoint purge \
  --profile-name "$profilename" \
  --endpoint-name "$ep" \
  --resource-group "$rg" \
  --content-paths '/*' \
  --subscription "$subscription"
