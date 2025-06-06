FROM mongo


RUN apt-get update && apt-get install -y mongodb-org-shell