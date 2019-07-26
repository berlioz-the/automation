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


########################################################
################ TERIMNAL OUTPUT #######################
########################################################

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

########################################################
################ COMMAND EXECUTION #####################
########################################################

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
    result=$(bash -c "$1")
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

########################################################
####################### LOGIC ##########################
########################################################

createServiceAccount() {
    SVC_ACCOUNT_NAME=$1
    SVC_ACCOUNT_ID=$SVC_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com

    print_status "Creating service account $SVC_ACCOUNT_NAME..."

    exec_cmd_no_bail_no_output \
        "gcloud iam service-accounts describe $SVC_ACCOUNT_ID" \
        result \
        return_code

    if [[ $return_code == "0" ]]; then
        echo "SvcAccount $SVC_ACCOUNT_NAME exists";
    else
        echo "SvcAccount $SVC_ACCOUNT_NAME does not exist, creating service account...";

        exec_cmd "gcloud iam service-accounts create $SVC_ACCOUNT_NAME --display-name=$SVC_ACCOUNT_NAME" \
            "ERROR: SvcAccount $SVC_ACCOUNT_NAME was not created" \
            "Reason: $result"

        print_status "Service account $SVC_ACCOUNT_NAME was created"
    fi
}

attachServiceAccountRole() {
    local serviceAccountId=$1
    local roleId=$2
    print_status "Attaching $roleId..."

    exec_cmd_no_output "gcloud projects add-iam-policy-binding $PROJECT_ID --member \"serviceAccount:$serviceAccountId\" --role \"$roleId\"" \
        "ERROR: Could not attach $roleId to $serviceAccountId" \
        "Reason: $result"
}

setupRoles() {

    role_name_arr=("roles/owner")

    print_status "Attaching roles..."
    for ((i=0; i<${#role_name_arr[@]}; i++)); do
        role_id=${role_name_arr[$i]}
        attachServiceAccountRole $SVC_ACCOUNT_ID $role_id
    done
}

createServiceAccountKey() {
    print_status "Setting up key for $SVC_ACCOUNT_ID..."

    CREDENTIALS_FILE=credentials.json

    exec_cmd "gcloud iam service-accounts keys list --iam-account=$SVC_ACCOUNT_ID" \
        "ERROR: Could not get service-account $SVC_ACCOUNT_ID keys" \
        "Reason: $result" \
        result
    CURRENT_KEYS_STR=$(echo "$result" | tail -n +2 | cut -d' ' -f1)
    CURRENT_KEYS_ARR=()
    while read -r line; do
        CURRENT_KEYS_ARR+=("$line")
    done <<< "$CURRENT_KEYS_STR"
    for ((i=0; i<${#CURRENT_KEYS_ARR[@]}-1; i++)); do
        key_id=${CURRENT_KEYS_ARR[$i]}
        print_status "Deleting key $key_id..."

        exec_cmd "gcloud iam service-accounts keys delete $key_id --iam-account=$SVC_ACCOUNT_ID --quiet" \
            "ERROR: Could not delete key $key_id for service-account $SVC_ACCOUNT_ID" \
            "Reason: $result"
    done

    print_status "Creating key for $key_id..."

    exec_cmd "gcloud iam service-accounts keys create $CREDENTIALS_FILE --iam-account=$SVC_ACCOUNT_ID --key-file-type=json" \
        "ERROR: Could not create key for SvcAccount $SVC_ACCOUNT_ID" \
        "Reason: $result"
        
    print_status "Key saved in: $CREDENTIALS_FILE"
}

setupServiceAccount() {
    SVC_ACCOUNT_NAME=$1
    SVC_ACCOUNT_ID=$SVC_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com

    createServiceAccount $SVC_ACCOUNT_NAME

    setupRoles

    createServiceAccountKey $SVC_ACCOUNT_NAME
}

confirmGCPAccount() {
    while true; do
        read -p "Should we use account [$GCP_ACCOUNT_ID]? (Y/n)" yn
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

print_header "GCP Project Creator" \
"Steps to be performed in this script:
1. Login to GCP account
2. Create service account ${bold}\"cicd-robot\"${normal}
4. Assign Owner role to service account ${bold}\"cicd-robot\"${normal}
5. Create key for service account ${bold}\"cicd-robot\"${normal}
"
pause_for 1

if [[ $QUIET ]]; then 
    print_status "In quiet mode."
fi

if [[ -z $PROJECT_ID ]]; then
    bail_with_error \
        "ERROR: Project name not provided. Usage:" \
        "create.sh -p <project-name>" 
fi 

print_status "Checking if GCloudSDK is installed"
exec_cmd "command -v gcloud" \
    "ERROR: Doesn't seem like you have Google Cloud SDK installed" \
    "You can install it from here: https://cloud.google.com/sdk/docs/quickstarts"

print_status "Getting GCP Account ID"
if [[ $QUIET ]]; then 
    fetchGCPAccoutId
    if [[ -z $GCP_ACCOUNT_ID ]]; then
        "ERROR: Not logged in to gcloud cli." \
        "Try running \"gcloud auth login\"." 
    fi 
else
    while true; do
        fetchGCPAccoutId
        if [[ -z $GCP_ACCOUNT_ID ]]; then
            print_status "Not logged in to GCP"
        else
            confirmGCPAccount
        fi 
        if [[ -z $GCP_ACCOUNT_ID ]]; then
            loginToGCP
        fi
        if [[ ! -z $GCP_ACCOUNT_ID ]]; then
            break;
        fi
    done
fi
print_status "Selected GCP Account: $GCP_ACCOUNT_ID"

print_status "Creating GCP Project $PROJECT_ID ..."

exec_cmd "gcloud projects create $PROJECT_ID" \
    "ERROR: Could not create new GCP project" \
    ""

print_status "Activating GCP Project..."

exec_cmd "gcloud config set project $PROJECT_ID" \
    "ERROR: Failed to set active project" \
    ""

print_status "Enabling APIs..."

exec_cmd "gcloud services enable cloudresourcemanager.googleapis.com" \
    "ERROR: Failed to enable APIs" \
    ""


SVC_ACCOUNT_NAME=cicd-robot

setupServiceAccount "$SVC_ACCOUNT_NAME"

print_header "GCP Project was successfully!" \
"
Credentials key is saved in: $CREDENTIALS_FILE
Remember to keep it safe!"
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
##################### RUNNING ##########################
########################################################
runner $1