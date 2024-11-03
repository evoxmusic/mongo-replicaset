FROM mongo:6.0.19

# Define build arguments
ARG MONGODB_USER
ARG MONGODB_PASSWORD

# Set environment variables
ENV MONGODB_INITDB_ROOT_USERNAME=$MONGODB_USER
ENV MONGODB_INITDB_ROOT_PASSWORD=$MONGODB_PASSWORD

# Create directories
RUN mkdir -p /data/db /docker-entrypoint-initdb.d

# Generate keyfile for replica set authentication
RUN mkdir -p /data/mongodb && \
    openssl rand -base64 756 > /data/mongodb/keyfile && \
    chown mongodb:mongodb /data/mongodb/keyfile && \
    chmod 400 /data/mongodb/keyfile

# Create the init script
RUN cat <<'EOF' > /docker-entrypoint-initdb.d/init.sh
#!/bin/bash
set -e

# Graceful shutdown function
cleanup() {
    echo "Received shutdown signal, initiating graceful shutdown..."
    if [ ! -z "$MONGOD_PID" ]; then
        # Send SIGTERM to mongod process instead of using shutdown command
        kill -TERM "$MONGOD_PID" || true
        # Wait for process to terminate with timeout
        timeout 30s tail --pid=$MONGOD_PID -f /dev/null || true
    fi
    exit 0
}

# Set up signal handling
trap cleanup SIGTERM SIGINT

# Check if data directory is empty
DATA_DIR="/data/db"
if [ -z "$(ls -A $DATA_DIR)" ]; then
    echo "Fresh installation detected, initializing MongoDB..."
    
    # Start MongoDB in the background with optimized settings
    mongod --bind_ip_all \
           --replSet rs0 \
           --setParameter enableTestCommands=1 \
           --setParameter skipShardingConfigurationChecks=true \
           --setParameter disableLogicalSessionCacheRefresh=true \
           --setParameter maxTransactionLockRequestTimeoutMillis=10000 & 
    
    MONGOD_PID=$!

    # More robust wait for MongoDB to start
    echo "Waiting for MongoDB to start..."
    max_tries=60
    counter=0
    until mongosh --quiet --eval "print('waiting...')" 2>/dev/null || [ $counter -gt $max_tries ]; do
        sleep 2
        counter=$((counter+1))
    done

    if [ $counter -gt $max_tries ]; then
        echo "Failed to connect to MongoDB after 120 seconds"
        exit 1
    fi

    echo "Initializing replica set with single node configuration..."
    mongosh --quiet --eval '
        rs.initiate({
            _id: "rs0",
            members: [{
                _id: 0,
                host: "localhost:27017",
                priority: 1
            }],
            settings: {
                chainingAllowed: true,
                heartbeatTimeoutSecs: 10,
                electionTimeoutMillis: 10000,
                catchUpTimeoutMillis: 10000
            }
        });
        
        // Wait for the replica set to initialize
        let timeout = 60000;
        let start = new Date().getTime();
        while (!rs.isMaster().ismaster && new Date().getTime() - start < timeout) {
            sleep(1000);
        }
        
        if (!rs.isMaster().ismaster) {
            throw new Error("Failed to initialize replica set");
        }
    '
    
    echo "Creating admin user..."
    mongosh admin --quiet --eval "db.createUser({user: '$MONGODB_INITDB_ROOT_USERNAME', pwd: '$MONGODB_INITDB_ROOT_PASSWORD', roles: ['root']})"
    
    echo "Shutting down initial MongoDB instance..."
    # Send SIGTERM instead of using shutdown command
    kill -TERM "$MONGOD_PID"
    # Wait for process to terminate with timeout
    timeout 30s tail --pid=$MONGOD_PID -f /dev/null || true
fi

echo "Starting MongoDB with authentication..."
exec mongod --bind_ip_all \
            --replSet rs0 \
            --auth \
            --keyFile /data/mongodb/keyfile \
            --setParameter enableTestCommands=1 \
            --setParameter skipShardingConfigurationChecks=true \
            --setParameter disableLogicalSessionCacheRefresh=true \
            --setParameter maxTransactionLockRequestTimeoutMillis=10000 
EOF

# Make script executable and set permissions
RUN chmod +x /docker-entrypoint-initdb.d/init.sh && \
    chown -R mongodb:mongodb /data/db /docker-entrypoint-initdb.d /data/mongodb

# Switch to mongodb user
USER mongodb

# Expose MongoDB port
EXPOSE 27017

# Set the entrypoint
ENTRYPOINT ["/docker-entrypoint-initdb.d/init.sh"]
