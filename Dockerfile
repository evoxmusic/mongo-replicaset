FROM mongo:6.0.19

# Create directory for mongodb data and scripts
RUN mkdir -p /data/db /docker-entrypoint-initdb.d

# Create init script
RUN cat <<'EOF' > /docker-entrypoint-initdb.d/init-replica.sh
#!/bin/bash
mongosh --eval "rs.initiate({ _id: \"rs0\", members: [{ _id: 0, host: \"localhost:27017\" }]})"
EOF

# Create a custom entrypoint script
RUN cat <<'EOF' > /custom-entrypoint.sh
#!/bin/bash
mongod --replSet rs0 --noauth --bind_ip_all &
sleep 5
/docker-entrypoint-initdb.d/init-replica.sh
wait
EOF

# Make scripts executable
RUN chmod +x /docker-entrypoint-initdb.d/init-replica.sh
RUN chmod +x /custom-entrypoint.sh

# Set proper permissions
RUN chown -R mongodb:mongodb /data/db /docker-entrypoint-initdb.d

# Expose the default MongoDB port
EXPOSE 27017

# Set the custom entrypoint
ENTRYPOINT ["/custom-entrypoint.sh"]
