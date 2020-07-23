FROM eu.gcr.io/quorumpreempt/adder-builder as build
WORKDIR /build

COPY . .
RUN task build

FROM gcr.io/distroless/base

WORKDIR /service

#COPY --from=build /build /build without this dlv ls can't work but that's ok
COPY --from=build /usr/local/bin/grpc_health_probe .
COPY --from=build /build/bin/proxy adder-proxy
COPY --from=build /build/bin/service adder-service

ENV PATH=/service

#ENV GOTRACEBACK=all
ENTRYPOINT ["/service/adder-proxy"]
