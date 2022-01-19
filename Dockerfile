FROM ubuntu:18.04

ENV DEBIAN_FRONTEND noninteractive

# prepare system
RUN apt-get update && apt-get install wget git build-essential python3.6 python3.6-dev python3-pip software-properties-common \
    openjdk-8-jre postgresql-server-dev-10 postgresql-plpython3-10 ca-certificates -y

RUN wget -qO key "https://debian.neo4j.com/neotechnology.gpg.key"
RUN apt-key add key && rm key
RUN echo 'deb https://debian.neo4j.com stable 3.5' > /etc/apt/sources.list.d/neo4j.list

RUN apt-get update && apt-get install neo4j=1:3.5.14 zip -y
RUN cd  /var/lib/neo4j/plugins/ && \
wget -q -O tmp.zip https://s3-eu-west-1.amazonaws.com/com.neo4j.graphalgorithms.dist/neo4j-graph-algorithms-3.5.14.0-standalone.zip && \
 unzip tmp.zip && rm tmp.zip
COPY neo4j.conf /etc/neo4j/neo4j.conf

# setup postgres
COPY postgres.conf /etc/postgresql/10/main/conf.d/cgrdb.conf
RUN echo "host all  all    0.0.0.0/0  md5" >> /etc/postgresql/10/main/pg_hba.conf
RUN echo "PATH = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'" >> /etc/postgresql/10/main/environment
USER postgres
RUN /etc/init.d/postgresql start && \
    psql --command "CREATE SCHEMA reactions;" && \
    psql --command "ALTER USER postgres WITH PASSWORD 'repathdb';"
USER root

# setup neo4j
RUN neo4j-admin set-initial-password 'repathdb'

# install CGRdb
RUN pip3 install -U pip
RUN git clone https://github.com/stsouko/smlar.git && \
    cd smlar && USE_PGXS=1 make && USE_PGXS=1 make install && cd .. & rm -rf smlar && \
    pip3 install -U numpy numba compress-pickle
RUN pip3 install -U dash-uploader  psycopg2-binary\
    git+https://github.com/cimm-kzn/CIMtools.git@master#egg=CIMtools \
    git+https://github.com/stsouko/CGRdb.git@4.0#egg=CGRdb[postgres] cgrtools[clean2djit,MRV]

# setup CGRdb
COPY config.json config.json
RUN service postgresql start &&\
 cgrdb init  -c '{"user":"postgres","password":"repathdb","host":"localhost"}' &&\
 cgrdb create -n "reactions" -f config.json -c '{"user":"postgres","password":"repathdb","host":"localhost"}' &&\
 rm config.json

# install RePathDB
COPY RePathDB tmp/RePathDB
COPY setup.py tmp/setup.py
COPY README.md tmp/README.md
COPY mol3d_dash-0.0.1-py3-none-any.whl tmp/mol3d_dash-0.0.1-py3-none-any.whl
COPY dash_network-0.0.1-py3-none-any.whl tmp/dash_network-0.0.1-py3-none-any.whl
RUN pip3 install /tmp/mol3d_dash-0.0.1-py3-none-any.whl && rm tmp/mol3d_dash-0.0.1-py3-none-any.whl
RUN pip3 install /tmp/dash_network-0.0.1-py3-none-any.whl && rm tmp/dash_network-0.0.1-py3-none-any.whl
RUN cd tmp && pip3 install . && rm -rf RePathDB setup.py README.md && cd ..
RUN service neo4j start && sleep 5 && neomodel_install_labels RePathDB RePathDB.graph --db bolt://neo4j:repathdb@localhost:7687 && service neo4j stop
# setup MarvinJS
COPY mjs /usr/local/lib/python3.6/dist-packages/RePathDB/wui/assets/mjs
COPY RePathDB /usr/local/lib/python3.6/dist-packages/RePathDBb/wui/assets/
COPY RePathDB/wui/assets/*.png /usr/local/lib/python3.6/dist-packages/RePathDB/wui/assets/
COPY boot.sh /opt/boot

#VOLUME ["/var/log/postgresql", "/var/lib/postgresql"]
EXPOSE 5000 7474 5432 7687

ENTRYPOINT ["/opt/boot"]
