# Install the application dependencies in a full UBI Node docker image
FROM registry.access.redhat.com/ubi9/nodejs-20:1-59.1725850623

# Copy package.json
COPY package.json ./

# Install app dependencies
RUN npm install --omit=dev

# Copy the dependencies into a minimal Node.js image
FROM registry.access.redhat.com/ubi8/nodejs-20-minimal:1-62.1724661480

# Install app dependencies
COPY --from=0 /opt/app-root/src/node_modules /opt/app-root/src/node_modules
COPY app.js /opt/app-root/src/
COPY package.json /opt/app-root/src/

ENV NODE_ENV production
ENV PORT 3000
EXPOSE 3000
CMD ["npm", "start"]