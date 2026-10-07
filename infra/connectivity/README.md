# US-only PoC connectivity

This isolated Terraform root creates a **new US VNet and private Linux VM** for synthetic-only PoC administration. It does not read, import, peer with or modify another project's resources. It is not a FIPS-validated VPN: [Tailscale documents its cryptographic limitations](https://tailscale.com/docs/concepts/tailscale-encryption). The application's platform/image/transport approval gates remain unchanged.

## Scope and prerequisites

| Setting | Behavior |
| --- | --- |
| Region | Explicit US region; recheck SKU restrictions, quota and the exact Ubuntu image before planning. |
| Network | New private `10.x.0.0/16`; verify it does not overlap the client's local or tailnet routes. |
| Subnets | Only the router's fourth `/24` first `/27` is created. Reserve the third `/24` for future private endpoints; no AI endpoint exists yet. |
| Internet | New Standard NAT gateway/public IP, outbound only. VM has no public IP. Default NSG outbound access permits package repositories, Tailscale coordination/relays and UDP traversal. This is not a production egress firewall. |
| Inbound | NSG denies unsolicited inbound, including direct VNet SSH/DNS; return traffic for outbound sessions is stateful. |
| OS | Exact Ubuntu 24.04 x64 image, Secure Boot/vTPM, key-only SSH, Standard SSD, managed boot diagnostics. No Azure identity or role grant is needed. |
| Provisioning | Signed stable Tailscale APT repository, DNS relay and forwarding. Node is **not enrolled**. Installed package version must be recorded during readiness checks. |
| DNS | `dnsmasq` binds only to `tailscale0`, forwarding to Azure DNS from inside the VNet. Future private zones must be linked to this new VNet. |
| Ownership | Resource group, VNet and VM have `prevent_destroy`. Later roots may own standalone PoC subnets but must not adopt this VNet or mix inline and standalone subnet declarations. |
| Cost | VM, disk, NAT gateway/public IP and traffic are billable. Foundation, Search, model usage and ACR build-pool costs are additional. |

Use the approved checkout and explicit selected subscription via standard `ARM_SUBSCRIPTION_ID`/CLI conventions. Do not change a shared CLI default. Compute and Network providers must already be registered; this root does not register them.

Static checks are `terraform init -backend=false`, `terraform fmt -check`, `terraform validate` and `terraform test` with the public key supplied ephemerally. The tests mock Azure and do not create resources or exercise live connectivity. Parse cloud-init and syntax-check its embedded provisioning script without executing it before generating a live plan.

## Configure, plan and approve

Copy the sanitized example to an ignored owner-only `terraform.tfvars`, enter the approved values, and set `poc_connectivity_approved = true` only for the approved synthetic-only use. Supply the existing SSH **public** key in an ephemeral environment variable. Never generate SSH private keys into state or put Tailscale auth keys in custom data, tfvars, plans, logs or chat.

Normally use secured remote state. A narrowly approved bootstrap exception allows **this connectivity root only** to use owner-only local state on the encrypted authoritative Mac while the private backend is unreachable. Platform and build-pool roots still require secured remote state. Keep local state/backups and saved plans on that host, out of Git, and obtain separate approval to create a backend and migrate with native `terraform init -migrate-state`. Do not create duplicate state or discard the local owner.

```sh
cd infra/connectivity
umask 077
set +x
export TF_VAR_admin_public_key="$(cat "$HOME/.ssh/id_ed25519.pub")"
terraform init -input=false
terraform fmt -check
terraform validate
terraform plan -input=false -out=connectivity.tfplan
# Review additions, cost, outbound exposure, state ownership and all deletions.
# Only after approval of this exact saved plan:
terraform apply connectivity.tfplan
unset TF_VAR_admin_public_key
```

Do not use automatic approval, targeted apply, imports or AZD. Changing source, inputs, subscription, region or state invalidates the reviewed plan. Keep the source published/reviewed before applying. Do not delete resources or state as a recovery step.

## Enroll and verify separately

An applied VM is not connected or ready. Before enrollment, use an approved Azure VM Run Command to check `cloud-init status --wait --long`, service status and the installed Tailscale version. Cloud-init errors must be investigated, not hidden by resetting its state or claiming provisioning success.

The operator runs the `tailscale_up_command` output through an explicitly approved VM Run Command and completes the interactive login themselves. Keep the enrollment URL out of chat. This command may time out while waiting for login; inspect `tailscale status` afterward rather than automatically retrying or supplying an auth key. Keep default subnet-route SNAT enabled.

The tailnet administrator separately approves this node, the advertised **PoC endpoint prefix only**, and least-privilege ACLs: authorized deployment/reviewer devices to required endpoint HTTPS, DNS TCP/UDP 53 to this node, and key-only SSH 22 for the operator. Do not advertise another project's prefixes or use an exit node. Route and DNS approval do not follow automatically from approving Terraform.

After enrollment, obtain the node's Tailscale IPv4 address and configure split DNS for the `split_dns_domains` output to that address. Normal service domains matter because clients first query them before following private-link CNAMEs. Do not point the Mac at Azure's `168.63.129.16` directly. Keep DNS restricted to authorized tailnet clients, not the Azure NIC or Internet.

After the separately deployed US foundation links its private zones and creates endpoints, verify normal service names resolve to the reserved private prefix, Mac route selection uses Tailscale, and HTTPS certificate/hostname validation succeeds without public-access exceptions. Container Apps internal hostnames and additional runtime prefixes may need a separately reviewed route/DNS change. Keep all checks synthetic.

## Foundation handoff

The `vnet` and `nat_gateway_id` outputs identify **new PoC-owned US resources** for subsequent reviewed plans. They are not permission to deploy the existing-resource scenario against unrelated infrastructure. The separately approved [`state-backend root`](../state-backend/README.md) owns the reserved private-endpoint subnet and PoC Blob DNS zone as well as private/keyless state storage; consume its outputs without recreating those resources. Create a new US Foundry account/project/prompt agent, approved US model deployments/defaults, Search S1 or higher, application Storage and runtime/build subnets through a separate reviewed foundation. The AI foundation is not implemented by this root.

All regional resources and model processing must remain in the United States. Global Azure control-plane services, Entra ID and Private DNS aren't region-pinned resources. Exclude Global model deployment SKUs; use an approved US Data Zone or supported US regional deployment. Review Content Understanding custom and native-skill processing boundaries independently. A US resource location alone is not a residency or FIPS guarantee.
