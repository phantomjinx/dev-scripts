#!/bin/bash

SYNDESIS_HOME=${HOME}/programming/java/syndesis

# Read the value of an option.
readopt() {
    filters="$@"

    next=false
    for var in "${ARGS[@]}"; do
        if $next; then
            echo $var
            break;
        fi

        for filter in $filters; do
            if [[ "$var" = ${filter}* ]]; then
                local value="${var//${filter}=/}"
                if [ "$value" != "$var" ]; then
                    echo $value
                    return
                fi
                next=true
            fi
        done
    done
}

# Checks if a flag is present in the arguments.
hasflag() {
    filters="$@"
    for var in ${ARGS[@]}; do
        for filter in $filters; do
          if [ "$var" = "$filter" ]; then
              echo 'true'
              return
          fi
        done
    done
}

appdir() {
  echo "${SYNDESIS_HOME}/app"
}

recreate_project() {
    local project=$1

    if [ -z "$project" ]; then
        echo "No project given"
        exit 1
    fi

    # Delete project if existing
    if oc get project "${project}" >/dev/null 2>&1 ; then
        echo =============== WARNING -- Going to delete project ${project}
        oc get all -n $project
        echo ============================================================
        read -p "Do you really want to delete the existing project $project ? yes/[no] : " choice
        echo
        if [ "$choice" != "yes" ] && [ "$choice" != "y" ]; then
           echo "Aborting on user's request"
           exit 1
        fi
        echo "Deleting project ${project}"
        oc delete project "${project}"
    fi

    # Create project afresh
    echo "Creating project ${project}"
    for i in {1..10}; do
        if oc new-project "${project}" >/dev/null 2>&1 ; then
            break
        fi
        echo "Project still exists. Sleeping 10s ..."
        sleep 10
    done
    oc project "${project}"
}

create_oauthclient() {
  local tag=${1:-}

  create_openshift_resource \
      "install/support/serviceaccount-as-oauthclient-restricted.yml" \
      "$tag"
}

create_openshift_resource() {
    local resource=${1:-}
    local tag="$(readopt --tag)"

    if [ -n "$tag" ]; then
        pushd $(appdir) >/dev/null
        git fetch --tags
        git show $tag:${resource} | oc create -f -
        popd >/dev/null
    else
        oc create -f $(appdir)/../$resource
    fi
}

# Try first a template with the tag as combination
get_template_name() {
    local template=$1
    local tag=${2:-}
    if [ -n "$tag" ]; then
        local candidate="$template-$tag"
        $(oc get template $candidate >/dev/null 2>&1)
        if [ $? -eq 0 ]; then
          echo $candidate
          return
        fi
    fi


    echo $template
}

create_and_apply_template() {
  local route="syndesis.birds-of-prey.phantomjinx.org.uk"
  local console="https://peregrine.birds-of-prey.phantomjinx.org.uk:8443"
  local template="syndesis-dev-s2i"
  local tag="$(readopt --tag)"
  local test_support="$(hasflag --test-support)"

  if [ -z "$route" ]; then
    echo "No route given"
    exit 1
  fi

  create_openshift_resource \
      "install/${template}.yml" \
      "$tag"

  local template_name=$(get_template_name $template $tag)
  # Use '-restricted' template for tag <= 1.2
  if [ -n "$tag" ] && [[ $tag =~ 1\.[12] ]]; then
    template_name="${template_name}-restricted"
  fi

  local optional_args=""
  if [ -n "$(readopt --memory-server)" ]; then
    optional_args="$optional_args -p SERVER_MEMORY_LIMIT=$(readopt --memory-server)"
  fi
  if [ -n "$(readopt --memory-meta)" ]; then
    optional_args="$optional_args -p META_MEMORY_LIMIT=$(readopt --memory-meta)"
  fi
  if [ $(hasflag --test-support) ]; then
    optional_args="$optional_args -p TEST_SUPPORT_ENABLED=true"
  fi

  oc new-app --template=${template_name} \
    -p ROUTE_HOSTNAME="${route}" \
    -p OPENSHIFT_CONSOLE_URL="${console}" \
    -p OPENSHIFT_MASTER="$(oc whoami --show-server)" \
    -p OPENSHIFT_PROJECT="$(oc project -q)" \
    -p OPENSHIFT_OAUTH_CLIENT_SECRET=$(oc sa get-token syndesis-oauth-client) \
    -p MVN_MIRROR_URL="http://peregrine:8081/repository/maven-public/" \
    -p GIT_REPO_URL="https://github.com/phantomjinx/syndesis" \
    -p GIT_REPO_BRANCH="template-step-wip" \
    $optional_args
}

ARGS=("$@")

# If a project is given, create it new or recreate it
project=$(readopt --project -p)
if [ -z $project ]; then
  project="syndesis"
fi
echo "Project being recreated: $project"

if [ -n "${project}" ]; then
  recreate_project $project
fi

create_oauthclient "$(readopt --tag)"

create_and_apply_template
