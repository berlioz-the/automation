#!/bin/bash

# Discussion, issues and change requests at:
#   https://support.berlioz.cloud
#
# Script to cleanup GCP Project after Kubernetes cluster is deleted.
# There are some resources likes LB and static IPs that GKE leaves behind.
#
# bash -c "$(curl -sL https://raw.githubusercontent.com/berlioz-the/automation/master/gcp/project/cleanup.sh)"
#   or
# bash -c "$(wget -qO- https://raw.githubusercontent.com/berlioz-the/automation/master/gcp/project/cleanup.sh)"
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

### 
BG_PIDS=()
exec_cmd_bg() {
    local result=''
    local return_code=''
    exec_cmd_no_bail "$1" result return_code &
    local mypid=$!
    echo "Started PID ${mypid}..."
    BG_PIDS+=(${mypid})
}

wait_bg_finish() {
    # echo "Waiting ..."
    echo "${BG_PIDS[*]}"
    for pid in ${BG_PIDS[*]}; do
        # echo "Waiting PID ${pid}..."
        wait $pid
    done
    echo "Waiting Completed."
    echo "${BG_PIDS[*]}"
}

##################


fetchGCPAccoutId() {
    exec_cmd "gcloud config list account --format \"value(core.account)\"" \
        "ERROR: Could not fetch current account id" \
        "Are you sure you are logged in to gcloud CLI? Try running \"gcloud auth login\"." \
        GCP_ACCOUNT_ID
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

##################

runner() {

print_header "GCP Account Cleanup Script" \
"Steps to be performed in this script:
1. ...
2. ...
3. ...
"
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

#####
#####
#####
print_status "Cleaning up forwarding rules"

exec_cmd "gcloud compute forwarding-rules list" \
    "ERROR: Could not get list of forwarding-rules" \
    "" \
    result
echo "${result}" | tail -n +2 | while read -r line
do
    local id=$(echo ${line} | awk '{print $1}')
    local region=$(echo ${line} | awk '{print $2}')
    print_status "Deleting rule ${id} in ${region}..."

    exec_cmd_bg "gcloud compute forwarding-rules delete \"${id}\" --quiet --region \"${region}\"" 
done
wait_bg_finish

#####
#####
#####
print_status "Cleaning up external ip addresses"

exec_cmd "gcloud compute addresses list --format=\"table(name,region,region)\"" \
    "ERROR: Could not get list of static addresses" \
    "" \
    result
echo "${result}" | tail -n +2 | while read -r line
do
    local id=$(echo ${line} | awk '{print $1}')
    local region=$(echo ${line} | awk '{print $2}')
    print_status "Deleting forwarding rule ${id} in ${region}..."

    exec_cmd_bg "gcloud compute addresses delete \"${id}\" --quiet --region \"${region}\"" 
done
wait_bg_finish

#####
#####
#####
print_status "Cleaning up firewall rules"

exec_cmd "gcloud compute firewall-rules list --filter=\"name~^k8s.*$\" --format=\"table(name,direction,network)\"" \
    "ERROR: Could not get list of firewall rules" \
    "" \
    result
echo "${result}" | tail -n +2 | while read -r line
do
    local id=$(echo ${line} | awk '{print $1}')
    print_status "Deleting firewall rule ${id}..."

    exec_cmd_bg "gcloud compute firewall-rules delete \"${id}\" --quiet" 
done
wait_bg_finish

#####
#####
#####
# print_status "Cleaning up instance groups"

# exec_cmd "gcloud compute instance-groups unmanaged list" \
#     "ERROR: Could not get list of instance groups" \
#     "" \
#     result
# echo "${result}" | tail -n +2 | while read -r line
# do
#     local id=$(echo ${line} | awk '{print $1}')
#     local region=$(echo ${line} | awk '{print $2}')
#     print_status "Deleting instance group ${id} at ${region}..."

#     exec_cmd_no_bail "gcloud compute instance-groups unmanaged delete \"${id}\" --zone \"${region}\" --quiet" \
#         delete_result \
#         delete_return_code
# done


#####
#####
#####
print_status "Cleaning up load balancer target pools"

exec_cmd "gcloud compute target-pools list" \
    "ERROR: Could not get list of load balancer target pools" \
    "" \
    result
echo "${result}" | tail -n +2 | while read -r line
do
    local id=$(echo ${line} | awk '{print $1}')
    local region=$(echo ${line} | awk '{print $2}')
    print_status "Deleting load balancer target pool ${id} at ${region}..."

    exec_cmd_bg "gcloud compute target-pools delete \"${id}\" --region \"${region}\" --quiet" 
done
wait_bg_finish

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

runner
