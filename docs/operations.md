# Runbooks

## Manual Scaling & Emergency Override
In the event the KEDA scaler provides incorrect values or the metrics API is unreachable, use the following to take manual control:
- To Pause Autoscaling: Set the ScaledObject to "paused" to prevent KEDA from fighting manual changes.
```
kubectl annotate scaledobject coolkit autoscaling.keda.sh/paused-replicas="50"
```
- To Resume: Remove the annotation to hand control back to the KEDA controller.
- Emergency Floor: If you need to ensure a minimum capacity regardless of the scaler, update minReplicaCount in the Helm values and redeploy.