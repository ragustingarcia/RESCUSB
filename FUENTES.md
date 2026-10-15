# RESCUSB | Fuentes oficiales

Consultadas el **15/10/2026**. Las versiones fijadas y sus SHA-256 están en `catalogo.json`; se contrastan con las publicaciones oficiales antes de preparar el USB. Windows se descubre dinámicamente para el idioma elegido.

| Componente | Fuente |
|---|---|
| Ventoy 1.1.18 | [Descarga oficial](https://www.ventoy.net/en/download.html), [release](https://github.com/ventoy/Ventoy/releases/tag/v1.1.18), [SHA-256](https://github.com/ventoy/Ventoy/releases/download/v1.1.18/sha256.txt) |
| SystemRescue 13.02 amd64 | [Página oficial](https://www.system-rescue.org/Download/), [SHA-256](https://www.system-rescue.org/releases/13.02/systemrescue-13.02-amd64.iso.sha256); descarga desde el CDN oficial enlazado por el proyecto |
| Hiren's BootCD PE 1.0.8 x64 | [Descarga y SHA-256](https://www.hirensbootcd.org/download/); el enlace del proyecto puede redirigir a un espejo HTTPS |
| Rescuezilla 2.6.2 resolute | [Página oficial](https://rescuezilla.com/download), [release](https://github.com/rescuezilla/rescuezilla/releases/tag/2.6.2), [SHA256SUM](https://github.com/rescuezilla/rescuezilla/releases/download/2.6.2/SHA256SUM) |
| Ubuntu Desktop 26.04.1 LTS amd64 | [Directorio oficial](https://releases.ubuntu.com/26.04/), [SHA256SUMS](https://releases.ubuntu.com/26.04/SHA256SUMS) |
| Memtest86+ 8.10 x86_64 GRUB | [Página oficial](https://memtest.org/), [SHA-256 del ZIP](https://memtest.org/download/v8.10/sha256sum.txt), [README de arranque](https://memtest.org/readme) |
| Windows 10 x64 | [Página pública de Microsoft](https://www.microsoft.com/en-us/software-download/windows10ISO) |
| Windows 11 x64 | [Página pública de Microsoft](https://www.microsoft.com/en-us/software-download/windows11) |

## Automatización de Windows

`Rescusb.Microsoft.psm1` consulta la página pública, su selector de edición y su tabla SHA-256 por idioma y arquitectura. Descubre los parámetros del cliente JavaScript publicado por Microsoft e inicializa la sesión anónima que esa página utiliza con `ov-df.microsoft.com`. Solo lee campos concretos; **no ejecuta JavaScript remoto**.

Los idiomas y enlaces se consultan en el servicio de la misma página, bajo `www.microsoft.com/software-download-connector/api/`. Es un flujo web público que puede cambiar; **no se presenta como una API de soporte estable de Microsoft**. Un rechazo, una edición ambigua, un hash ausente o un cambio de estructura detienen la preparación antes del borrado. No se eluden denegaciones ni se cambia de red/ubicación.

Las ISO se aceptan únicamente desde los nombres exactos de servidores Microsoft permitidos, por HTTPS, con arquitectura x64, identidad de versión y hash oficial. El programa no contiene enlaces firmados reutilizados ni los guarda en los informes. Se auditaron como referencia de interoperabilidad el cliente público de Microsoft y [Fido, del autor de Rufus](https://github.com/pbatard/Fido); Fido no es una dependencia, no se incluye su código y no se ejecuta.

## Arranque y formato

- [CLI de Ventoy](https://www.ventoy.net/en/doc_windows_cli.html): `VTOYCLI /I /PhyDrive:n /FS:EXFAT`, MBR y soporte Secure Boot por defecto. El resultado se confirma mediante `cli_done.txt`, donde 0 significa éxito.
- [Búsqueda de imágenes](https://www.ventoy.net/en/doc_search_path.html): `.ventoyignore` excluye una carpeta y sus descendientes del menú.
- [Secure Boot](https://www.ventoy.net/en/doc_secure.html) y [Memdisk / Ctrl+D](https://www.ventoy.net/en/doc_memdisk.html): comportamiento del firmware y alternativa para algunas imágenes pequeñas. RESCUSB no cambia el firmware.
- [Oscdimg de Microsoft](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/oscdimg-command-line-options?view=windows-11): admite ISO9660, Joliet y UDF, incluido UDF sin ISO9660. El reconocimiento de formato contempla ambos tipos y no sustituye SHA-256.
- [ECMA-167](https://dev.ecma-international.org/wp-content/uploads/ECMA-167_2nd_edition_december_1994.pdf): estructura de reconocimiento UDF. Se comprueba una secuencia reconocible BEA01 / NSR02 o NSR03 / TEA01.

## Controles de Windows

- [Win32_DiskDrive](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-diskdrive): clasificación del medio y capacidad 7 de medios extraíbles. Se exige además evidencia USB, identidad completa y exclusión de discos protegidos.
- [Etiquetas de puntos de análisis](https://learn.microsoft.com/en-us/windows/win32/fileio/reparse-point-tags): permite distinguir la familia Cloud Files de OneDrive de enlaces y junctions. Solo se acepta la familia Cloud Files conocida; las etiquetas desconocidas se rechazan.
- [Manual de curl](https://curl.se/docs/manpage.html#--max-filesize): desde 8.4.0 se interrumpen también transferencias que exceden el límite sin tamaño conocido de antemano. Es la versión mínima exigida; en este equipo se comprobó curl 8.21.0.

El kit de autoría usa la identidad canónica de **[Rodolfo Agustín García](https://ragustingarcia.com/)**. No se publicó una web de RESCUSB ni se modificó ese dominio.
