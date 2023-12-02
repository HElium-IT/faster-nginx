# Docker Compose Stack

This repository contains the docker-compose.yaml file and the build.sh script to configure and run a stack of services using Docker Compose.

### Contents

- docker-compose.yaml: The main file that defines the services, networks, and volumes used in the stack.

- build.sh: The script for building the stack. This script handles pulling the latest versions of services from the repositories, creating ssl key and certificate, building the nginx.conf and starting the containers.

### Requirements

Docker: Make sure you have Docker installed on your system.

## Stack Configuration via stack.json

The stack.json file can be used to configure the stack; it is used to pass arguments to the build.sh script.

### Gitlab Access Token

If you want to automatically pull the stack repositories you will need to:

- create a gitlab access token if you haven't done it before:
  - The token name and expiration can be whatever you like
  - The only scope needed is "read_repository"
  - [Create access token](https://gitlab.intranet.bit4id.com/profile/personal_access_tokens)
- copy the token, as plain text, in the ".git-token" file in the main directory

### Host setting

When developing on a private pc, it's a MUST to modify the host file and add all the network connection u need.
Let's look at this example case:

- we are buiding a stack with a backend server and a frontend server
- we choose "mystack.com" as common name.

We are gonna add this lines to the host file:

```
    127.0.0.1 mystack.com
    127.0.0.1 api.mystack.com
    127.0.0.1 web.mystack.com
```

The host file can be found here:

```
[LINUX]
    /etc/hosts
[WINDOWS]
    C:\Windows\System32\drivers\etc\hosts
```

## Build and run the Builder

Build the image:

```
    docker build --no-cache -t nginx_builder .
```

Run this command to get help:

_(--rm removes container after exit)_

```
    docker run --rm nginx_builder --help
```

---

At this point one important command is --init

It is used to generate the folders based on the repositories and the stages in the stack.json config file

_(-v .:/app sets the volume in order to output the builded files)_

_(OR -v ${PWD}:/app if your docker version is before 24.0)_

```
    docker run --rm -v .:/app nginx_builder --init
```

After the initialization you can use the command --stage=STAGE to crate the docker-compose file

```
    docker run --rm -v .:/app nginx_builder --stage=dev
```

---

Clear builder image:

```
    docker rmi nginx_builder
```

## SSL Configuration

The builder can receive the flag --ssl=PWD and it works like this:

- if there are "server.crt" and "server.key" files in /nginx/ssl folder, do nothing.
- if there is a "bundle.pfx" pkcs12 file in the /nginx/ssl folder, than create the server.crt and server.key files.
- if there is no file or even no /nginx/ssl folder, than create the certificate, the key and the pcks12 file.

TODO: The password PWD is in clear, find a way to set it up as a secret without being in the interactive cmd.

## Environment configuration

Environment variables needed in the container can be passed in the docker compose for the specified service or set up in the /nginx/env/$STAGE/.env file

## Build and Run the docker Compose Stack

Run the stack:

```
    docker compose up -d
```

Attach to logs:

```
    docker compose logs -f
```

Stop the compose:

```
    docker compose down
```

Remove volumes and images:

```
    docker compose down -v --rmi all
```

## Certificate Installation

Every time a new certificate gets created during the building process, you will see an error when navigating to the services: "NET::ERR\*CERT_AUTHORITY_INVALID".

To solve the issue just press "Advanced" -> "Proceed to mystack.com (unsafe)".
