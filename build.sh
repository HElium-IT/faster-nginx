#!/bin/sh

# Parse configuration from the stack.json file
CONFIG_FILE="stack.json"

# Parse and extract git information from the JSON config
GITLAB_URL=$(jq -r '.gitlab_url' $CONFIG_FILE)
GIT_ACCESS_TOKEN_FILE=$(jq -r '.git_access_token_file' $CONFIG_FILE)

# stack.json validation
validate_stack_json() {
    echo "---Validating stack.json structure..."

    # Validate main keys
    jq -e '
        .git_access_token_file and (.git_access_token_file | type=="string") and
        .gitlab_url and (.gitlab_url | type=="string")
    ' stack.json > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Validation of main keys in stack.json failed. Exiting."
        exit 1
    fi

    # Validate repositories
    jq -e '
        .repositories and
        (.repositories | type=="array") and
        (.repositories[] | 
            .alias and (.alias | type=="string") and
            .name and (.name | type=="string") and
            .url and (.url | type=="string")
        )
    ' stack.json > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Validation of repositories in stack.json failed. Exiting."
        exit 1
    fi

    # Validate stages
    jq -e '
        .stages and
        (.stages | type=="array") and
        (.stages[] | 
            .alias and (.alias | type=="string") and
            .common_name and (.common_name | type=="string") and
            .docker_compose_file and (.docker_compose_file | type=="string") and
            .repositories and (.repositories | type=="array") and
            (.repositories[] | 
                .alias and (.alias | type=="string") and
                (
                    (.branch and (.branch | type=="string")) or
                    (.tag and (.tag | type=="string"))
                )
            )
        )
    ' stack.json > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Validation of stages in stack.json failed. Exiting."
        exit 1
    fi
    
    echo "---Validation of stack.json passed."
}

# initialization function
init_environment() {
  local stages=$(jq -r '.stages[] | .alias' $CONFIG_FILE)
  
  # 1: Create Docker Compose Template Files
  for stage in $stages; do
    local compose_file="docker-compose.${stage}-template.yaml"
    
    if [ ! -f "$compose_file" ]; then
      touch "$compose_file"
      echo "# Docker Compose Template for ${stage}" > "$compose_file"
      cat "docker-compose.template.yaml" >> "$compose_file"
    fi
  done
  
  # 2: Create Nginx Config Folders and Template Files
  for stage in $stages; do
    local config_dir="./nginx/config/${stage}"
    local env_dir="./nginx/env/${stage}"

    if [ ! -d "$config_dir" ]; then
      mkdir -p "$config_dir"
    fi
    if [ ! -d "$env_dir" ]; then
      mkdir -p "$env_dir"
    fi
    
    local repositories=$(jq -r --arg STAGE "$stage" '.stages[] | select(.alias == $STAGE) | .repositories[] | .alias' $CONFIG_FILE)
    # if repositories is empty, call create_empty_dir_dummy
    if [ -z "$repositories" ]; then
      create_empty_dir_dummy "$config_dir"
    fi
    for repo in $repositories; do
      local config_file="./nginx/config/${stage}/${repo}.conf.template"
      if [ ! -f "$config_file" ]; then
        touch "$config_file"
        echo "# Nginx Configuration for ${repo} in ${stage}" > "$config_file"
        # ... (Add additional default contents if needed)
      fi

      local env_file="./nginx/env/${stage}/${repo}.env"
      if [ ! -f "$env_file" ]; then
        echo "# This variables get integrated into the configuration templates with envsubst" > "$env_file"
        # ... (Add additional default environment variables if needed)
      fi
    done
  done
}

#cleaning function
clean_environment() {
  # STAGES CLEANING
  local stages=$(jq -r '.stages[] | .alias' $CONFIG_FILE)
  echo "---Cleaning stages"

  # Iterate through each stage for cleanup
  for stage in $stages; do
    # 1: Remove Nginx Config Folders for stage
    local config_dir="./nginx/config/${stage}"
    if [ -d "$config_dir" ]; then
      rm -r "$config_dir"
      echo " - config dir: $config_dir"
    fi

    # 2: Remove Nginx Env Folders for stage
    local env_dir="./nginx/env/${stage}"
    if [ -d "$env_dir" ]; then
      rm -r "$env_dir"
      echo " - env dir : $env_dir"
    fi

    # 3: Remove Docker Compose Template File for stage
    local compose_file="docker-compose.${stage}-template.yaml"
    if [ -f "$compose_file" ]; then
      rm "$compose_file"
      echo " - compose file template: $compose_file"
    fi
  done

  # REPOSITORIES CLEANING
  local repositories=$(jq -r '.repositories[] | .url' $CONFIG_FILE)
  echo "---Cleaning repositories"
  
  # Iterate through each repository and take it's name for cleanup
  for repo_url in $repositories; do
    # Extracting the repo name from its URL
    local repo_name=$(basename "$repo_url" .git)

    # If directory exists, remove it
    if [ -d "$repo_name" ]; then
      rm -r "$repo_name"
      echo " - repository folder: $repo_name"
    fi
  done
}

# git and repositories functions
setup_git_and_login() {
  if [ ! -f $GIT_ACCESS_TOKEN_FILE ]; then
    echo "---Error: Git access token file not found: $GIT_ACCESS_TOKEN_FILE"
    exit 1
  fi
  
  local git_access_token=$(cat "$GIT_ACCESS_TOKEN_FILE")
  git config --global credential.helper "store --file ~/.git-credentials"
  echo "https://oauth2:$git_access_token@$GITLAB_URL" >> ~/.git-credentials

  echo "---Git setup complete. You are now logged in."
}

pull_latest() {
  local repository_url="$1"
  local branch="$2"
  local tag="$3"

  local repo_name=$(basename "$repository_url" .git)
  local folder_name="./$repo_name"

  echo "---Pulling latest changes from $repo_name, branch: $branch, tag: $tag"
  if [ ! -d "$folder_name" ]; then
    git clone --recurse-submodules "$repository_url" "$folder_name" &>/dev/null || { echo "---Error: Failed to clone repository."; exit 1; }
  fi

  cd "$folder_name" || { echo "---Error: Failed to access repository folder."; exit 1; }
  git fetch --all --tags &>/dev/null || { echo "---Error: Failed to fetch latest changes."; exit 1; }

  if [ -n "$tag" ]; then
    git checkout "tags/$tag" &>/dev/null || { echo "---Error: Failed to checkout tag $tag."; exit 1; }
  else
    git checkout "$branch" &>/dev/null || { echo "---Error: Failed to checkout branch $branch."; exit 1; }
  fi

  git pull || { echo "---Error: Failed to pull latest changes."; exit 1; }
  git submodule update --init --recursive || { echo "---Error: Failed to update submodules."; exit 1; }

  cd - >/dev/null  # Return to the previous directory
}

pull_repositories() {
  local stage_alias="$1"
  local repositories=$(jq -r --arg STAGE "$stage_alias" '.stages[] | select(.alias == $STAGE) | .repositories[] | .alias' $CONFIG_FILE)

  for repo_alias in $repositories; do
    # Get the repository URL
    local repo_url=$(jq -r --arg ALIAS "$repo_alias" '.repositories[] | select(.alias == $ALIAS) | .url' $CONFIG_FILE)
    if [ "$repo_url" == "null" ]; then
      echo "---Error: Repository URL not found for alias: $repo_alias"
      exit 1
    fi

    # Get the branch
    local branch=$(jq -r --arg STAGE "$stage_alias" --arg ALIAS "$repo_alias" '.stages[] | select(.alias == $STAGE) | .repositories[] | select(.alias == $ALIAS) | .branch' $CONFIG_FILE)
    if [ "$branch" == "null" ]; then
      branch=""
    fi

    # Get the tag
    local tag=$(jq -r --arg ALIAS "$repo_alias" '.repositories[] | select(.alias == $ALIAS) | .tag' $CONFIG_FILE)
    if [ "$tag" == "null" ]; then
      tag=""
    fi

    # check if we have at least one of the two tag and branch
    if [ -z "$branch" ] && [ -z "$tag" ]; then
      echo "---Error: Branch/tag not found for alias: $repo_alias"
      exit 1
    fi

    # Call your pull_latest function or any other logic you might have
    pull_latest "$repo_url" "$branch" "$tag"
  done
}

# Docker Compose functions
substitute_word() {
  local file_path="$1"
  local word="$2"
  local substitute="$3"
  local output_file="$4"

  # Check if the file exists
  if [ ! -f "$file_path" ]; then
    echo "---Error: File not found: $file_path"
    exit 1
  fi
  
  # Check if the output file is specified
  if [ -z "$output_file" ]; then
    echo "---Warning: Output file not specified. The original file will be overwritten."
    output_file="$file_path"
    echo "---Output file: $output_file"
  fi

  # Substitute the words in the file, save the output to a temporary file and then substitute the original file with the temporary file
  sed "s/$word/$substitute/g" "$file_path" > "$output_file.tmp" && mv "$output_file.tmp" "$output_file" || { echo "---Error: Failed to substitute word."; exit 1; }
}

build_docker_compose(){
  local stage_alias="$1"
  
  local common_name=$(jq -r --arg STAGE "$stage_alias" '.stages[] | select(.alias == $STAGE) | .common_name' $CONFIG_FILE)
  local docker_compose_file=$(jq -r --arg STAGE "$stage_alias" '.stages[] | select(.alias == $STAGE) | .docker_compose_file' $CONFIG_FILE)

  local output="docker-compose.yaml"

  # Substitute variables of the template file
  substitute_word "./$docker_compose_file" "\${COMMON_NAME}" "$common_name" "./$output"
  substitute_word "./$output" "\${STAGE}" "$stage" "./$output"

  echo "---Docker compose file built: $output"
}

# SSL function
setup_ssl() {
  local stage_alias="$1"
  local pkcs12_pwd="$2"
  local common_name=$(jq -r --arg STAGE "$stage_alias" '.stages[] | select(.alias == $STAGE) | .common_name' $CONFIG_FILE)
  # "./nginx/ssl/server.key"
  # "./nginx/ssl/server.crt"
  
  # check if this files exists, if not generate them
  if [ -f "./nginx/ssl/server.key" ] && [ -f "./nginx/ssl/server.crt" ]; then
    echo "---SSL certificate and key files already exist."
    return 0
  fi

  # check if bundle.pfx exists and, if it does, generate the key and certificate files from it
  if [ -f "./nginx/ssl/bundle.pfx" ]; then
    echo "---PKCS_12 file found."
    openssl pkcs12 -in "./nginx/ssl/bundle.pfx" -nocerts -out "./nginx/ssl/server.key" -nodes -passin pass:$pkcs12_pwd -passout pass:$pkcs12_pwd
    openssl pkcs12 -in "./nginx/ssl/bundle.pfx" -nokeys -out "./nginx/ssl/server.crt" -passin pass:$pkcs12_pwd -passout pass:$pkcs12_pwd
    echo "---New SSL certificate and key files generated from the PKCS_12 file."
    return 0
  fi

  if [ ! -e "./nginx/ssl" ]; then
    mkdir -p ./nginx/ssl
  fi

  openssl req -newkey rsa:2048 -nodes -keyout ./nginx/ssl/server.key -x509 -days 365 -out ./nginx/ssl/server.crt \
    -subj "/C=IT/ST=Campania/L=Napoli/O=Bit4Id/OU=R&D/CN=${common_name}" -passout pass:$pkcs12_pwd >/dev/null 2>&1

  # openssl pkcs12 -export -in ./nginx/ssl/server.crt -inkey ./nginx/ssl/server.key -out ./nginx/ssl/bundle.pfx -passout pass:$pkcs12_pwd

  echo "---New self-signed SSL certificate and keys files generated."
}

# Dummy for empty folders

create_empty_dir_dummy() {
  local dir=$1
  
  # Create directory if not exists
  mkdir -p "$dir"
  
  # If directory is empty, create a dummy file
  if [ -z "$(ls -A "$dir")" ]; then
    touch "$dir/dummy.template"
    touch "$dir/dummy.conf"
    echo "Created dummy files in: $dir"
  fi
}

# Check functions
check_stage_existency(){
  # check if stage is in the stack.json file, if it is return true, else print all the stages aliases and return false
  local stage_alias="$1"
  local stages=$(jq -r '.stages[] | .alias' $CONFIG_FILE)
  for stage in $stages; do
    if [ "$stage" == "$stage_alias" ]; then
      return 0
    fi
  done

  echo "---Error: Invalid stage: $stage_alias"
  echo "Available stages:"
  for stage in $stages; do
    echo " - $stage"
  done
  return 1
}

# Function to display the help menu
# TODO: Update the help menu with the stack.json implementation
display_help() {
  echo "Usage: build.sh [OPTIONS]"
  echo "Build the Nginx configuration based on the template for development."
  echo
  echo "Options:"
  echo "  --init                    Initialize the folder structure and files based on the stack.json stages and repositories"
  echo "  --clear                   Clean the folder structure and files based on the stack.json stages and repositories"
  echo "  --ssl=PASSWORD            Generate SSL certificate and key files from the PKCS_12 file, if it exists, or generate them from scratch with the specified password"
  echo "  --stage=STAGE             Set the stage, will impact docker compose and nginx configuration (default: '$default_stage')"
  echo "  --help                    Display this help menu"
  echo
  echo "Example:"
  echo "  ./build.sh --stage=dev"
  echo
}


# Parse command-line arguments
setup_ssl_flag=0
while [ $# -gt 0 ]; do
  case "$1" in
    --help)
      display_help
      exit 1
      ;;
    --init)
      validate_stack_json
      init_environment
      exit 0
      ;;
    --clear)
      validate_stack_json
      clean_environment
      exit 0
      ;;
    --ssl=*)
      setup_ssl_flag=1
      ssl_pwd="${1#*=}"
      ;;
    --stage=*)
      validate_stack_json
      check_stage_existency "${1#*=}" || exit 1
      stage="${1#*=}"
      ;;
    *)
      echo "Error: Invalid argument or command: $1"
      echo
      display_help
      exit 1
      ;;
  esac
  shift
done

# Check if the stage is specified
if [ -z "$stage" ]; then
  echo "Error: Stage not specified."
  echo
  display_help
  exit 1
fi

if [ $setup_ssl_flag -eq 1 ]; then
  setup_ssl "$stage" "$ssl_pwd"
fi

# Build the main docker-compose.yaml file based on the stage template
build_docker_compose "$stage"

# Setup git and login, then pull the latest changes from the repositories
setup_git_and_login
pull_repositories "$stage"

