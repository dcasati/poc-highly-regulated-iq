# Official Microsoft architecture icons

The SVGs in this directory are **unchanged official Microsoft assets**, copied
from the supplied `Azure_Public_Service_Icons` collection. `manifest.json`
records each original collection-relative path and SHA-256. The diagram files
embed these same SVG bytes for offline use; nothing is
uploaded to a diagram service.

Source and permitted use:
[Azure Architecture Center — icons and terms](https://learn.microsoft.com/azure/architecture/icons/).
Microsoft permits these icons in architectural diagrams, training materials
and documentation; do not crop, flip, rotate, distort or use them as your own
product's logo. Microsoft retains the product icons and trademarks. The supplied
collection also contains `Microsoft_Terms_of_Use.pdf` and `Azure_Icons_FAQ.pdf`;
those original documents remain with the user's source collection.

Service names, not a similar-looking glyph, define the diagram boundaries:

- **Entra ID** uses the supplied *Entra Identity Roles and Administrators*
  glyph to illustrate its Caseworker/Reviewer role boundary, **not** a fabricated
  Entra brand logo. An Entra ID brand glyph was not in this collection.
- **Container Apps** uses the *Container Apps Environments* glyph: ingress is
  the actual Managed Environment private endpoint.
- **Blob Storage** uses the *Storage Accounts* family glyph; originals/state
  and the two published containers are separate logical data boundaries in
  application storage, not necessarily different storage accounts.
- **Content Understanding** uses the *Cognitive Services* family glyph. The
  application custom analyzer and Search native layout skill are distinct calls.
- **Azure AI Search** uses the official *Cognitive Search* glyph (the filename's
  legacy service name); **Foundry IQ** uses its supplied official icon.
  **Azure OpenAI / AI Services account** uses the supplied Foundry family glyph,
  not a claim that Managed Agent Service is deployed. The retained historical
  animation may use the Agent Service icon; it is not the current architecture.
- **Virtual Networks** and **Container Registries** use their exact service
  glyphs. The build pool is infrastructure supporting image delivery, not a
  document-processing step.
