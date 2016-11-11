FROM node:4
RUN mkdir /kragnoth
WORKDIR /kragnoth

# Do this separately to cache the npm step.
COPY package.json ./
RUN npm install --silent

COPY lib lib
COPY static static
COPY views views
COPY app.coffee app.coffee

EXPOSE 9000 9001 9002
CMD ["./node_modules/.bin/coffee", "app.coffee"]
