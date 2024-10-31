FROM mongo:6.0.19

# Create directory for mongodb data
RUN mkdir -p /data/db

# Set proper permissions
RUN chown -R mongodb:mongodb /data/db

# Copy any custom configuration if needed
COPY mongod.conf /etc/mongod.conf

# Expose the default MongoDB port
EXPOSE 27017

# Command to run MongoDB with replica set
CMD ["mongod", "--replSet", "rs0", "--noauth", "--bind_ip_all"]

# Note: Using --bind_ip_all allows connections from other containers
