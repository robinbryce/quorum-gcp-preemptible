FROM eu.gcr.io/quorumpreempt/adder-builder as build
WORKDIR /tmp/work

COPY . .
RUN task build

FROM gcr.io/distroless/base

WORKDIR /service

COPY --from=build /usr/local/bin/grpc_health_probe .
COPY --from=build /tmp/work/bin/proxy adder-proxy
COPY --from=build /tmp/work/bin/service adder-service

ENV PATH=/service

ENTRYPOINT ["/service/adder-proxy"]
