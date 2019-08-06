#!/bin/bash

# Discussion, issues and change requests at:
#   https://support.berlioz.cloud
#
# Script to configure GCP Project with Berlioz service account,
# IAM roles and other dependencies.
#
# bash -c "$(curl -sL https://raw.githubusercontent.com/berlioz-the/automation/master/gcp/project/init.sh)"
#   or
# bash -c "$(wget -qO- https://raw.githubusercontent.com/berlioz-the/automation/master/gcp/project/init.sh)"
#

if test -t 1; then # if terminal
    ncolors=$(which tput > /dev/null && tput colors) # supports color
    if test -n "$ncolors" && test $ncolors -ge 8; then
        termcols=$(tput cols)
        bold="$(tput bold)"
        underline="$(tput smul)"
        standout="$(tput smso)"
        normal="$(tput sgr0)"
        black="$(tput setaf 0)"
        red="$(tput setaf 1)"
        green="$(tput setaf 2)"
        yellow="$(tput setaf 3)"
        blue="$(tput setaf 4)"
        magenta="$(tput setaf 5)"
        cyan="$(tput setaf 6)"
        white="$(tput setaf 7)"
    fi
fi

print_status() {
    echo
    echo "## $1"
    echo
}

pause_for() {
    print_status "Continuing in $1 seconds ..."
    sleep $1
}

print_bold() {
    local title="$1"
    local text="$2"

    echo
    echo "${red}================================================================================${normal}"
    echo "${red}================================================================================${normal}"
    echo
    echo -e "  ${bold}${yellow}${title}${normal}"
    echo
    echo -en "  ${text}"
    echo
    echo "${red}================================================================================${normal}"
    echo "${red}================================================================================${normal}"
}

print_header() {
    local title="$1"
    local text="$2"

    echo
    echo "${red}================================================================================${normal}"
    echo "${red}================================================================================${normal}"
    echo
    echo -e "  ${bold}${green}${title}${normal}"
    echo
    echo -en "  ${text}"
    echo
    echo "${red}================================================================================${normal}"
    echo "${red}================================================================================${normal}"
}

bail() {
    echo 'Error executing command, exiting'
    exit 1
}

bail_with_error() {
    print_bold "$1" "$2"
    bail
}

raw_exec_cmd() {
    echo "+ $1"
    bash -c "$1"
}

exec_cmd_no_bail_no_output() {
    local  __resultvar=$2
    local  __returncodevar=$3
    echo "+ $1"
    result=$(bash -c "$1" 2>&1) # dzec
    return_code=$(echo $?)
    eval $__resultvar="'$result'"
    eval $__returncodevar="'$return_code'"
}

exec_cmd_no_bail() {
    exec_cmd_no_bail_no_output "$1" result return_code
    echo "$result"
    local  __resultvar=$2
    local  __returncodevar=$3
    eval $__resultvar="'$result'"
    eval $__returncodevar="'$return_code'"
}

exec_cmd() {
    exec_cmd_no_bail "$1" result return_code
    if [[ $return_code != "0" ]]; then
        bail_with_error "$2" "$3"
    fi
    if [[ ! -z ${4+x} ]]; then
        local  __resultvar=$4
        eval $__resultvar="'$result'"
    fi
}

exec_cmd_no_output() {
    exec_cmd_no_bail_no_output "$1" result return_code
    if [[ $return_code != "0" ]]; then
        bail_with_error "$2" "$3"
    fi
    if [[ ! -z ${4+x} ]]; then
        local  __resultvar=$4
        eval $__resultvar="'$result'"
    fi
}

##################

createServiceAccount() {
    SVC_ACCOUNT_NAME=$1
    SVC_ACCOUNT_ID=${SVC_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com

    print_status "Creating service account ${SVC_ACCOUNT_NAME}..."

    exec_cmd_no_bail_no_output \
        "gcloud iam service-accounts describe \"${SVC_ACCOUNT_ID}\"" \
        result \
        return_code

    if [[ $return_code == "0" ]]; then
        echo "Service account ${SVC_ACCOUNT_NAME} exists";
    else
        echo "Service account ${SVC_ACCOUNT_NAME} does not exist, creating service account...";

        exec_cmd "gcloud iam service-accounts create \"${SVC_ACCOUNT_NAME}\" --display-name=\"${SVC_ACCOUNT_NAME}\"" \
            "ERROR: Service account ${SVC_ACCOUNT_NAME} was not created" \
            "Reason: $result"

        print_status "Service account ${SVC_ACCOUNT_NAME} was created"
    fi
}

concat_line() {
    prefix=$1
    suffix=$2
    echo "${prefix}${suffix}\n"
}

createRole() {
    local role_name=$1
    final_role_name=berlioz.${role_name}
    print_status "Querying role: ${final_role_name}..."
    local role_id="projects/${PROJECT_ID}/roles/berlioz.${role_name}"

    local role_title=${ROLE_NAMES[${role_name}]}
    local role_permissions_str=${ROLE_PERMISSIONS[${role_name}]}

    TMP_ROLE_FILE=berlioz-role-$$.yaml

    echo "title: ${role_title}" > ${TMP_ROLE_FILE}
    echo "name: ${role_id}" >> ${TMP_ROLE_FILE}
    echo "description: ${role_title} Role" >> ${TMP_ROLE_FILE}
    echo "stage: GA" >> ${TMP_ROLE_FILE}
    echo "includedPermissions:" >> ${TMP_ROLE_FILE}

    IFS=$'\n'
    read -d '' -r -a role_permissions_arr <<< "${role_permissions_str[functions]}"
    for i in "${role_permissions_arr[@]}"; do # access each element of array
        echo "- ${i}" >> ${TMP_ROLE_FILE}
    done
    IFS=' '

    exec_cmd_no_bail_no_output \
        "gcloud iam roles describe \"${final_role_name}\" --project \"${PROJECT_ID}\"" \
        existing_role \
        existing_role_result

    if [[ $existing_role_result == "0" ]]; then

        is_deleted_value=$(echo "${existing_role}" | grep "^deleted: true")
        if [[ ! -z ${is_deleted_value} ]]; then
            print_status "Undeleting Role: ${final_role_name}..."

            exec_cmd \
                "gcloud iam roles undelete \"${final_role_name}\" --project \"${PROJECT_ID}\"" \
                result \
                return_code

            print_status "Querying the role after undelete: ${final_role_name}..."
            exec_cmd_no_bail_no_output \
                "gcloud iam roles describe \"${final_role_name}\" --project \"${PROJECT_ID}\"" \
                existing_role \
                existing_role_result
        fi
    fi

    if [[ ${existing_role_result} == "0" ]]; then

        print_status "Updating Role: ${final_role_name}..."

        etag_value=$(echo "$existing_role" | grep "^etag\:")
        echo -e "${role_data}" >> ${TMP_ROLE_FILE}

        exec_cmd_no_bail \
            "gcloud iam roles update \"${final_role_name}\" --project \"${PROJECT_ID}\" --file \"${TMP_ROLE_FILE}\" --quiet" \
            result \
            return_code

        rm ${TMP_ROLE_FILE}
        if [[ ${return_code} != "0" ]]; then
            bail_with_error \
                "ERROR: Could not update role ${final_role_name}" \
                "Reason: ${result}";
        else
            print_status "Role ${final_role_name} updated"
        fi
    else
        print_status "Creating Role: ${final_role_name}..."

        exec_cmd_no_bail \
            "gcloud iam roles create \"${final_role_name}\" --project \"${PROJECT_ID}\" --file \"${TMP_ROLE_FILE}\" --quiet" \
            result \
            return_code

        rm ${TMP_ROLE_FILE}
        if [[ ${return_code} != "0" ]]; then
            bail_with_error \
                "ERROR: Could not create role ${final_role_name}" \
                "Reason: ${result}";
        else
            print_status "Role ${final_role_name} created"
        fi
    fi
}

attachServiceAccountRole() {
    local serviceAccountId=$1
    local roleId=$2
    print_status "Attaching ${roleId}..."

    exec_cmd_no_output "gcloud projects add-iam-policy-binding \"${PROJECT_ID}\" --member \"serviceAccount:${serviceAccountId}\" --role \"${roleId}\"" \
        "ERROR: Could not attach ${roleId} to ${serviceAccountId}" \
        ""
}


setupRoles() {
    print_status "Creating roles..."

    for role_key in "${!ROLE_NAMES[@]}"
    do
        role_id="projects/${PROJECT_ID}/roles/berlioz.${role_key}"
        createRole ${role_key}
        attachServiceAccountRole ${SVC_ACCOUNT_ID} ${role_id}
    done

    default_role_arr=("roles/container.admin" "roles/iam.serviceAccountUser")
    for role_id in "${default_role_arr}"
    do
        attachServiceAccountRole ${SVC_ACCOUNT_ID} ${role_id}
    done
}

createServiceAccountKey() {
    print_status "Setting up key for ${SVC_ACCOUNT_ID}..."

    CREDENTIALS_FILE=credentials.json

    exec_cmd "gcloud iam service-accounts keys list --iam-account=\"${SVC_ACCOUNT_ID}\"" \
        "ERROR: Could not get service-account ${SVC_ACCOUNT_ID} keys" \
        "" \
        result
    echo "${result}" | cut -d' ' -f1 | tail -n +2 | sed -e '$ d' | while read -r key_id
    do
        print_status "Deleting key ${key_id}..."

        exec_cmd "gcloud iam service-accounts keys delete \"${key_id}\" --iam-account=\"${SVC_ACCOUNT_ID}\" --quiet" \
            "ERROR: Could not delete key ${key_id} for service-account ${SVC_ACCOUNT_ID}" \
            ""
    done

    print_status "Creating key for ${key_id}..."

    exec_cmd "gcloud iam service-accounts keys create \"${CREDENTIALS_FILE}\" --iam-account=\"${SVC_ACCOUNT_ID}\" --key-file-type=json" \
        "ERROR: Could not create key for service account ${SVC_ACCOUNT_ID}" \
        ""

    print_status "Key saved in: ${CREDENTIALS_FILE}"
}

setupServiceAccount() {
    SVC_ACCOUNT_NAME=$1
    SVC_ACCOUNT_ID=${SVC_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com

    createServiceAccount ${SVC_ACCOUNT_NAME}

    setupRoles

    createServiceAccountKey ${SVC_ACCOUNT_NAME}
}

confirmGCPAccount() {
    while true; do
        read -p "Should we use account [${GCP_ACCOUNT_ID}]? (Y/n)" yn
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) GCP_ACCOUNT_ID=; break;;
            * ) break;;
        esac
    done
}

loginToGCP() {
    raw_exec_cmd "gcloud auth login"
}

fetchGCPAccoutId() {
    exec_cmd "gcloud config list account --format \"value(core.account)\"" \
        "ERROR: Could not fetch current account id" \
        "Are you sure you are logged in to gcloud CLI? Try running \"gcloud auth login\"." \
        GCP_ACCOUNT_ID
}

##################

runner() {

print_header "Berlioz GCP Account Setup Script" \
"Steps to be performed in this script:
1. Login to GCP account
2. Create service account ${bold}\"berlioz-robot\"${normal}
3. Create necessary iam roles
4. Assign roles to  service account ${bold}\"berlioz-robot\"${normal}
5. Create key for service account ${bold}\"berlioz-robot\"${normal}
"
pause_for 1

if [[ ${QUIET} ]]; then
    print_status "In quiet mode."
fi

print_status "Checking if GCloudSDK is installed"
exec_cmd "command -v gcloud" \
    "ERROR: Doesn't seem like you have Google Cloud SDK installed" \
    "You can install it from here: https://cloud.google.com/sdk/docs/quickstarts" \

print_status "Getting GCP Account ID"
if [[ ${QUIET} ]]; then
    fetchGCPAccoutId
    if [[ -z ${GCP_ACCOUNT_ID} ]]; then
        "ERROR: Not logged in to gcloud cli." \
        "Try running \"gcloud auth login\"."
    fi
else
    while true; do
        fetchGCPAccoutId
        if [[ -z ${GCP_ACCOUNT_ID} ]]; then
            print_status "Not logged in to GCP"
        else
            confirmGCPAccount
        fi
        if [[ -z ${GCP_ACCOUNT_ID} ]]; then
            loginToGCP
        fi
        if [[ ! -z ${GCP_ACCOUNT_ID} ]]; then
            break;
        fi
    done
fi
print_status "Selected GCP Account: ${GCP_ACCOUNT_ID}"

print_status "GCP Project"
if [[ -z ${PROJECT_ID} ]]; then
    exec_cmd_no_output "gcloud projects list" \
        "ERROR: Could not get list of GCP projects" \
        "" \
        result

    PROJECT_ID_LIST=($(echo "${result}" | tail -n +2 | cut -d' ' -f1))
    PROJECT_COUNT=${#PROJECT_ID_LIST[@]}
    print_status "Choose GCP Project below:"
    for ((i=0; i<PROJECT_COUNT; i++)); do
        project_id=${PROJECT_ID_LIST[$i]}
        project_index=$((i+1))
        echo "${project_index}) ${project_id}"
    done
    if [[ $QUIET ]]; then
        if [[ -z ${PROJECT_ID} ]]; then
            bail_with_error "ERROR. Using quiet mode but project id is not provided.";
        fi
    else
        while true; do
            read -p "Select project: " select_project_index
            re='^[0-9]+$'
            if [[ ${select_project_index} =~ $re ]] ; then
                if [[ "${select_project_index}" -gt "0" && "${select_project_index}" -le "${PROJECT_COUNT}" ]]; then
                    select_project_index=$((select_project_index-1))
                    PROJECT_ID=${PROJECT_ID_LIST[${select_project_index}]}
                    break;
                else
                    echo "ERROR. Invalid input. Index out of range.";
                fi
            else
                echo "ERROR. Invalid input. Not a number";
            fi
        done
    fi
fi
print_status "Using project: ${PROJECT_ID}"

exec_cmd "gcloud config set project \"${PROJECT_ID}\"" \
    "ERROR: Failed to set active project" \
    ""

SVC_ACCOUNT_NAME=berlioz-robot

setupServiceAccount "${SVC_ACCOUNT_NAME}"

print_header "GCP Account configured successfully!" \
"You can now link the key with Berlioz account.

Credentials key is saved in: ${CREDENTIALS_FILE}
Remember to keep it safe!

Details here:
    https://docs.berlioz.cloud/cloud/gcp/account-setup/#link-gcp-with-berlioz"
}


########################################################
########### SETTING COMMAND LINE ARGUMENTS #############
########################################################
POSITIONAL=()
while [[ $# -gt 0 ]]
do
    key="$1"
    case $key in
        -p|--project)
        PROJECT_ID="$2"
        shift # past argument
        shift # past value
        ;;
        -q|--quiet)
        QUIET="YES"
        shift # past argument
        ;;
        *)    # unknown option
        POSITIONAL+=("$1") # save it in an array for later
        shift # past argument
        ;;
    esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters


########################################################
########### SETTING UP IAM ROLES #######################
########################################################
declare -A ROLE_NAMES
declare -A ROLE_PERMISSIONS

ROLE_NAMES[cloudsql]="Berlioz CloudSQL"
ROLE_PERMISSIONS[cloudsql]="
cloudsql.instances.create
cloudsql.instances.delete
cloudsql.instances.get
cloudsql.instances.import
cloudsql.instances.list
cloudsql.instances.update"

ROLE_NAMES[functions]="Berlioz Functions"
ROLE_PERMISSIONS[functions]="
cloudfunctions.functions.create
cloudfunctions.functions.delete
cloudfunctions.functions.get
cloudfunctions.functions.list
cloudfunctions.functions.update
cloudfunctions.locations.list
cloudfunctions.operations.get
cloudfunctions.operations.list"

ROLE_NAMES[iam]="Berlioz IAM"
ROLE_PERMISSIONS[iam]="
iam.serviceAccountKeys.create
iam.serviceAccountKeys.delete
iam.serviceAccountKeys.get
iam.serviceAccountKeys.list
iam.serviceAccounts.create
iam.serviceAccounts.delete
iam.serviceAccounts.getIamPolicy
iam.serviceAccounts.setIamPolicy
iam.serviceAccounts.update
resourcemanager.projects.getIamPolicy
resourcemanager.projects.setIamPolicy"

ROLE_NAMES[pubsub]="Berlioz PubSub"
ROLE_PERMISSIONS[pubsub]="
pubsub.subscriptions.create
pubsub.subscriptions.delete
pubsub.subscriptions.get
pubsub.subscriptions.getIamPolicy
pubsub.subscriptions.list
pubsub.subscriptions.setIamPolicy
pubsub.subscriptions.update
pubsub.topics.attachSubscription
pubsub.topics.create
pubsub.topics.delete
pubsub.topics.get
pubsub.topics.getIamPolicy
pubsub.topics.list
pubsub.topics.setIamPolicy
pubsub.topics.update"

ROLE_NAMES[serviceusage]="Berlioz Service Usage"
ROLE_PERMISSIONS[serviceusage]="
serviceusage.services.get
serviceusage.services.enable"

ROLE_NAMES[storage]="Berlioz Storage"
ROLE_PERMISSIONS[storage]="
storage.buckets.create
storage.buckets.delete
storage.buckets.get
storage.buckets.getIamPolicy
storage.buckets.list
storage.buckets.setIamPolicy
storage.buckets.update
storage.objects.create
storage.objects.delete
storage.objects.get
storage.objects.list
storage.objects.update"


########################################################
##################### RUNNING ##########################
########################################################
runner $1
