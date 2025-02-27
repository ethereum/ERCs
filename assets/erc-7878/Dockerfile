# Use Node.js as the base image
FROM node:22

# Set the working directory
WORKDIR /app

# Install necessary dependencies
RUN apt-get update && apt-get install -y \
    git \
    python3 \
    make \
    g++

# Copy package.json and package-lock.json
COPY package*.json ./

# Install project dependencies
RUN npm install

# Copy the rest of the project files
COPY . .

# Compile the Solidity contracts
RUN npx hardhat compile

# Run tests
CMD ["npx", "hardhat", "test"]

