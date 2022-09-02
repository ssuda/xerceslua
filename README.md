## Introduction

Update .env with Kong EE License (If required), Kong version and Postgres version

Start Kong and Database containers using docker-compose, before docker-compose up, we need to run database migrations

```shell
docker-compose run kong kong migrations bootstrap
docker-compose up -d
```

## Install OAS Validation Plugin
```shell
docker compose exec -it --user root kong luarocks install /opt/conf/lua-resty-openapi3-deserializer-2.0.0-1.all.rock --force 
docker compose exec -it --user root kong luarocks install xml2lua
docker compose exec -it --user root kong apk add xerces-c-dev g++
docker compose cp ./kong-plugin/kong/plugins/oas-validation/. kong:/usr/local/share/lua/5.1/kong/plugins/oas-validation
docker compose exec -it --user root kong bash -c 'cd /usr/local/share/lua/5.1/kong/plugins/oas-validation/xerceslua && luarocks make'
docker compose exec --user kong -e KONG_PLUGINS="bundled,oas-validation" kong kong reload
```

## Add a service

```shell
http POST :8001/services name=example-service url=http://httpbin.org
```

## Add a Route to the Service

```shell
http POST :8001/services/example-service/routes name=example-route paths:='["/"]'
```

## Add Plugin to the Service

```shell
http -f :8001/services/example-service/plugins name=oas-validation config.api_spec="@kong-plugin/spec/fixtures/resources/NAB Payments API - swagger.json" config.xsd_specs\[1\].name=pain.xsd config.xsd_specs\[1\].schema=@kong-plugin/spec/fixtures/resources/pain.001.001.06.xsd
```

## Test

```shell
cat kong-plugin/kong/plugins/oas-validation/xerceslua/test/pain.xml | http POST :8000/v1/payments/payment-initiation Content-Type:application/xml 
```

## Cleanup
```shell
docker-compose down
```