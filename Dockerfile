FROM alpine:3.14

# Install dependencies
RUN apk add --no-cache \
    git \
    openssl \
    jq
        
# Set the working directory
WORKDIR /app

# Copy the needed files
COPY stack.json .
COPY .git-token .
COPY build.sh .
COPY docker-compose.*-template.* .

# Make the build.sh script executable
RUN ["chmod", "+x", "./build.sh"]

# Set the entrypoint to the build.sh script
ENTRYPOINT ["./build.sh"]