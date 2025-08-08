FROM node:18-alpine
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm install --production
COPY orchestrator_server.js ./ 
COPY public ./public
COPY config ./config
EXPOSE 4000
CMD ["npm","start"]
