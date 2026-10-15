# RESCUSB | Kit de autoría

Identidad **personal**, visibilidad **full**. Autor: **Rodolfo Agustín García**. Web canónica del autor: [ragustingarcia.com](https://ragustingarcia.com/). Person estable: `https://ragustingarcia.com/#person`. Localidad pública: Tigre, Buenos Aires, AR.

Se aplicó el kit local `kit-seo-autor`, con sus referencias personal y checklist técnico. La autoría aparece en la terminal, README, comentarios del código, package.json, identidad.json, HTML estático, JSON-LD, humans.txt, ai.txt y llms.txt. La identidad visual propia usa fondo #0b141c, cian #38d9e8 y verde #b9ef70. La imagen Open Graph tiene 1200 × 630 píxeles y pesa menos de 300 KB; el favicon es vectorial.

## Piezas incluidas

`index.html`, `assets/og-image.png`, `assets/favicon.svg`, `schema.json`, `package.json`, `identidad.json`, `robots.txt`, `ai.txt`, `llms.txt`, `humans.txt`, `sitemap.xml` y README con atribución. El HTML contiene title, description, author, theme-color, Open Graph/Twitter y el grafo SoftwareApplication/Person estático.

## Adaptación a un programa local

El código fuente está publicado en [github.com/ragustingarcia/RESCUSB](https://github.com/ragustingarcia/RESCUSB), declarado como `sameAs` del software en el JSON-LD y como `repository` en package.json e identidad.json. No existe una web propia de RESCUSB ni una ficha de tienda. Por eso **no se inventan canonical, og:url, downloadUrl ni una URL de imagen pública**. La imagen se referencia como archivo local. El identificador del software es `urn:rescusb:software`; el del autor mantiene su URL canónica. El sitemap no contiene URLs inventadas. Los crawlers están permitidos en robots.txt, pero este archivo local todavía no se sirve desde un hosting. La ficha HTML local usa noindex hasta asignar y verificar el origen público.

Esto mantiene el paquete completo sin confundir la autoría real con una publicación inexistente. **Preparado localmente no significa publicado, indexable ni indexado.** No se modificó ragustingarcia.com ni se publicó una web propia ni un release.

## Al publicar, completar con la URL real

1. Decidir la superficie pública: página propia, repo o ficha de tienda. Revisar el modelo de uso y la licencia antes de liberar código.
2. Añadir canonical y og:url; convertir og:image/twitter:image y el url/image del software en direcciones absolutas existentes, y retirar noindex de la ficha pública. El @id de Person no cambia.
3. Llenar el sitemap con URLs que devuelvan 200 y agregar la línea Sitemap a robots.txt.
4. Comprobar el robots servido y sus cabeceras desde el hosting real, incluidos los bots de IA. El archivo del paquete por sí solo no prueba su estado público.
5. Validar rich preview y JSON-LD en los servicios de destino; registrar el dominio y sitemap en Search Console/Bing cuando corresponda.

No se asignan precios, una licencia pública, un store ID o una aprobación comercial que todavía no se definieron. La metadata conserva `UNLICENSED` y el repo incluye un `LICENSE` propietario: uso sin cargo, sin redistribución. Los componentes de terceros mantienen sus derechos y condiciones.
