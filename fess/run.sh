#!/bin/bash

ES_LOGFILE=/var/log/elasticsearch/elasticsearch.log

if [ x"$ES_HTTP_URL" = "x" ] ; then
  ES_HTTP_URL=http://localhost:9200
else
  sed -i -e "s|^ES_HTTP_URL=.*|ES_HTTP_URL=$ES_HTTP_URL|" /etc/default/fess
fi

if [ x"$ES_TRANSPORT_URL" = "x" ] ; then
  ES_TRANSPORT_URL=localhost:9300
else
  sed -i -e "s|^ES_TRANSPORT_URL=.*|ES_TRANSPORT_URL=$ES_TRANSPORT_URL|" /etc/default/fess
fi

if [ "x$FESS_CONTEXT_PATH" != "x" ]; then
    echo "export FESS_CONTEXT_PATH=$FESS_CONTEXT_PATH" >> /etc/default/fess
    URL_PING_FESS="http://localhost:8080/${FESS_CONTEXT_PATH}/json/ping"
else
    URL_PING_FESS="http://localhost:8080/json/ping"
fi

if [ x"$PING_RETRIES" = "x" ] ; then
  PING_RETRIES=3
fi

if [ x"$PING_INTERVAL" = "x" ] ; then
  PING_INTERVAL=60
fi

start_elasticsearch() {
  touch $ES_LOGFILE
  chown elasticsearch:elasticsearch $ES_LOGFILE
  tail -f ${ES_LOGFILE} &

  if [ x"$ES_JAVA_OPTS" != "x" ] ; then
    echo "ES_JAVA_OPTS=$ES_JAVA_OPTS" >> /etc/default/elasticsearch
  fi
  service elasticsearch start

  counter=1
  ret=1
  while [ $ret != 0 -a $counter -le 60 ] ; do
    echo "Checking Elasticsearch status #$counter"
    grep "started" $ES_LOGFILE > /dev/null 2>&1
    ret=$?
    counter=`expr $counter + 1`
    sleep 1
  done

}

start_fess() {
  touch /var/log/fess/fess-crawler.log \
        /var/log/fess/fess-suggest.log \
        /var/log/fess/fess-thumbnail.log \
        /var/log/fess/audit.log \
        /var/log/fess/fess.log
  chown fess:fess /var/log/fess/fess-crawler.log \
                  /var/log/fess/fess-suggest.log \
                  /var/log/fess/fess-thumbnail.log \
                  /var/log/fess/audit.log \
                  /var/log/fess/fess.log
  tail -f /var/log/fess/*.log &
  service fess start
}

wait_app() {
  while [ 1 ] ; do
    if [ x"$RUN_ELASTICSEARCH" != "xfalse" ] ; then
      STATUS=`curl -w '%{http_code}\n' -s -o /dev/null http://localhost:9200`
      if [ x"$STATUS" = x200 ] ; then
        ELASTICSEARCH_ERROR_COUNT=0
      else
        ELASTICSEARCH_ERROR_COUNT=`expr $ELASTICSEARCH_ERROR_COUNT + 1`
      fi
      if [ $ELASTICSEARCH_ERROR_COUNT -ge $PING_RETRIES ] ; then
        echo "Elasticsearch is not available."
        exit 1
      fi
    fi
    if [ x"$RUN_FESS" != "xfalse" ] ; then
      STATUS=`curl -w '%{http_code}\n' -s -o /dev/null ${URL_PING_FESS}`
      if [ x"$STATUS" = x200 ] ; then
        FESS_ERROR_COUNT=0
      else
        FESS_ERROR_COUNT=`expr $FESS_ERROR_COUNT + 1`
      fi
      if [ $FESS_ERROR_COUNT -ge $PING_RETRIES ] ; then
        echo "Fess is not available."
        exit 1
      fi
    fi
    sleep $PING_INTERVAL
  done
}

if [ x"$RUN_ELASTICSEARCH" != "xfalse" ] ; then
  start_elasticsearch
fi

curl --retry 30 --retry-connrefused -XGET "$ES_HTTP_URL/_cluster/health?wait_for_status=yellow&timeout=3m"

if [ x"$RUN_FESS" != "xfalse" ] ; then
  start_fess
fi

if [ x"$RUN_SHELL" = "xtrue" ] ; then
  /bin/bash
else
  wait_app
fi
