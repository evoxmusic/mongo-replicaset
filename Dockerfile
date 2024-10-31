FROM mongo:6.0.19

# Create directory for mongodb data and scripts
RUN mkdir -p /data/db /docker-entrypoint-initdb.d

# Create init script
RUN echo 'mongosh --eval "rs.initiate({ _id: \"rs0\", members: [{ _id: 0, host: \"localhost:27017\" }]})"' > /docker-entrypoint-initdb.d/init-replica.sh

# Make the init script executable
RUN chmod +x /docker-entrypoint-initdb.d/init-replica.sh

# Create a custom entrypoint script
RUN echo '#!/bin/bash\
mongod --replSet rs0 --noauth --bind_ip_all &\
sleep 5\
/docker-entrypoint-initdb.d/init-replica.sh\
wait' > /custom-entrypoint.sh

# Make the entrypoint script executable
RUN chmod +x /custom-entrypoint.sh

# Set proper permissions
RUN chown -R mongodb:mongodb /data/db /docker-entrypoint-initdb.d

# Expose the default MongoDB port
EXPOSE 27017

# Set the custom entrypoint
ENTRYPOINT ["/custom-entrypoint.sh"]
