#/bin/sh
kubectl create --save-config -f namespace.yaml
kubectl create --save-config -f deployment.yaml
kubectl create --save-config -f service.yaml
