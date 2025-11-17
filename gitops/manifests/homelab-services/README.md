# Homelab Services

This directory contains custom Kubernetes manifests for homelab-specific applications.

## Structure

- `whoami.yaml` - Example application for testing ingress and service mesh
- Add more YAML files here for your custom applications

## Adding New Services

1. Create new YAML files in this directory
2. Ensure proper namespace is set (usually `homelab`)
3. Include appropriate labels and selectors
4. Consider resource limits and requests
5. Add ingress rules if external access is needed

## Best Practices

- Use consistent labeling across all resources
- Set appropriate resource limits
- Include health checks when applicable
- Use ConfigMaps and Secrets for configuration
- Follow Kubernetes security best practices