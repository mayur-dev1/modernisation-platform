#!/bin/bash

basedir=modernisation-platform-environments/terraform/environments
networkdir=core-repo/environments-networks
templates=core-repo/terraform/templates/*.tf
environment_json_dir=core-repo/environments

provision_environment_directories() {
  # This reshapes the JSON for subnet sets to include the business unit, pulled from the filename; and the set name from the key of the object:
  # [
  #   {
  #     "subnet_sets": [
  #       {
  #         "cidr": "10.233.8.0/21",
  #         "accounts": [
  #           "nomis",
  #           "oasys",
  #         ],
  #         "set": "general",
  #         "business-unit": "hmpps"
  #       },
  #       {
  #         "cidr": "10.233.16.0/21",
  #         "accounts": [
  #           "delius"
  #         ],
  #         "set": "delius",
  #         "business-unit": "hmpps"
  #       }
  #     ]
  #   }...
  # ]
  networking_definitions=$(jq -n '[ inputs | { subnet_sets: .cidr.subnet_sets | to_entries | map_values(.value + { set: .key, "business-unit": input_filename | ltrimstr("environments-networks/") | rtrimstr(".json") | split("-")[0] } ) } ]' "$networkdir"/*.json)

  for file in $environment_json_dir/*.json; do

    echo "This is file: $file"
    application_name=$(basename "$file" .json)
    echo "This is the application name: $application_name"
    directory=$basedir/$application_name
    echo "This is the directory: $directory"
    account_type=$(jq -r '."account-type"' ${environment_json_dir}/${application_name}.json)

    if [ -d $directory ] || [ "$account_type" = "core" ]; then

      # Do nothing if a directory already exists
      echo ""
      echo "Ignoring $directory, it already exists or is a core account"
      echo ""
    else
      # Create the directory and copy files if it doesn't exist
      echo ""
      echo "Creating $directory"

      mkdir -p "$directory"
      copy_templates "$directory" "$application_name"
    fi

    # This filters and reshapes networking_definitions to only include the business units and subnet sets for $APPLICATION_NAME
    # e.g. if hmpps-production.json and laa-production.json both contained subnet-sets that specified the account "core-sandbox",
    # and $APPLICATION_NAME was core-sandbox, it would output this:
    # [
    #   {
    #     "business-unit": "hmpps",
    #     "set": "general"
    #   },
    #   {
    #     "business-unit": "laa",
    #     "set": "general"
    #   }
    # ]

    # check if /environments-networks files exists for this application
    FILE_EXISTS=`jq --arg APPLICATION_NAME "$application_name" '.[].subnet_sets[] | select(.accounts[] | contains($APPLICATION_NAME))' <<< "$networking_definitions"`
    if [[ ${FILE_EXISTS} ]]
    then
      # set up raw jq data that includes application name, business unit and subnet-set
      RAW_OUTPUT=`jq --arg APPLICATION_NAME "$application_name" 'limit(1;.[].subnet_sets[] | select(.accounts[] | contains($APPLICATION_NAME)) | { "business-unit": ."business-unit", "set": .set, "application": $APPLICATION_NAME } )' <<< "$networking_definitions"`
    else
      # set up raw jq data that includes application name, blank business unit and blank subnet-set
      RAW_OUTPUT=`jq -n --arg APPLICATION_NAME "$application_name" '{ "business-unit": "", "set": "", "application": $APPLICATION_NAME }'`
    fi
    # wrap raw json output with a header and store the result in the applications folder
    jq -rn --argjson DATA "${RAW_OUTPUT}" '{ networking: [ $DATA ] }' > "$directory"/networking.auto.tfvars.json
  done
}

copy_templates() {

  for file in $templates; do
    filename=$(basename "$file")

    if [ ${filename} != "subnet_share.tf" ]
    then
      echo "Copying $file to $1, replacing application_name with $application_name"
      sed "s/\$application_name/${application_name}/g" "$file" > "$1/$filename"
      if [ ${filename} == "backend.tf" ]
      then
        if [ `uname` = "Linux" ]
        then
          sed -i "s/environments\//environments\/members\//g" "$1/$filename"
        else
          # This must be a Mac
          sed -i '' "s/environments\//environments\/members\//g" "$1/$filename"
        fi
      fi
    fi
  done

  echo "Finished copying templates."
}

provision_environment_directories