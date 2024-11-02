FROM mongo:6.0.19

# Define build arguments
ARG MONGODB_USER
ARG MONGODB_PASSWORD

# Validate build arguments
RUN if [ -z "$MONGODB_USER" ] || [ -z "$MONGODB_PASSWORD" ]; then \
    echo "Error: MONGODB_USER and MONGODB_PASSWORD build arguments must be provided" && \
    exit 1; \
    fi

# Create directory for mongodb data and scripts
RUN mkdir -p /data/db /docker-entrypoint-initdb.d

# Generate keyfile for replica set authentication
RUN mkdir -p /data/mongodb && \
    openssl rand -base64 756 > /data/mongodb/keyfile && \
    chown mongodb:mongodb /data/mongodb/keyfile && \
    chmod 400 /data/mongodb/keyfile

# Create init script for replica set and root user
RUN cat <<EOF > /docker-entrypoint-initdb.d/init-mongo.js
admin = db.getSiblingDB("admin");
admin.createUser({
  user: "$MONGODB_USER",
  pwd: "$MONGODB_PASSWORD",
  roles: ["root"]
});
EOF

RUN cat <<EOF > /docker-entrypoint-initdb.d/init-replica.sh
#!/bin/bash
sleep 10
mongosh --eval "rs.initiate({ _id: 'rs0', members: [{ _id: 0, host: 'localhost:27017' }]})"
EOF

# Make scripts executable
RUN chmod +x /docker-entrypoint-initdb.d/init-replica.sh

# Set proper permissions
RUN chown -R mongodb:mongodb /data/db /docker-entrypoint-initdb.d /data/mongodb

# Expose the default MongoDB port
EXPOSE 27017

# Use the official MongoDB entrypoint
CMD ["mongod", "--replSet", "rs0", "--auth", "--keyFile", "/data/mongodb/keyfile", "--bind_ip_all"]
