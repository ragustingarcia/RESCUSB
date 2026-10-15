# RESCUSB 2.1.0 | Validación

Fecha: **15/10/2026**. Motor probado: **Windows PowerShell 5.1**, el mismo que usa INICIAR.bat.

## Pruebas automáticas sin dispositivos reales

**101 casos aprobados, 0 fallos**: 72 pruebas de controles y transferencias en `tests/Probar.ps1`, 23 pruebas de automatización, integración y autoría en `tests/Probar-Rescusb.ps1`, y 6 regresiones adicionales en `tests/Probar-Revalidacion.ps1`.

## Cambios de 2.1.0

En la prueba real, Microsoft volvió a negar el enlace automático, y en un navegador de Windows su página manda a la herramienta de creación de medios. La ISO que genera esa herramienta no tiene hash publicado, así que con la 2.0.3 Windows nunca podía completarse.

- **Windows va siempre por la herramienta oficial de Microsoft.** Se eliminó el flujo que pedía enlaces a los servicios internos de Microsoft (sesión anónima y API de descarga): siempre era rechazado. Antes de borrar el pendrive, RESCUSB busca una ISO ya creada. Si no hay, explica que **tarda de 20 minutos a más de una hora**, ofrece crearla (Enter elige esta opción) y espera.
- **La herramienta solo se ejecuta firmada.** Se baja de los `go.microsoft.com` oficiales y se ejecuta solo con firma Authenticode válida de Microsoft Corporation. Antes de abrirla se explica qué elegir y se advierte que no hay que elegir «Unidad flash USB».
- **La ISO se verifica por firma.** Se monta en solo lectura y se exige firma válida de Microsoft en `setup.exe` y `sources\setup.exe`. Con DISM, la primera imagen tiene que ser x64, del idioma elegido y de la versión correcta. Se copia con su SHA-256 propio y el informe la marca como verificada por firma. Si hay una ISO que coincide con el hash publicado en la página de Microsoft, se prefiere esa.
- **Windows 10 opcional.** Sin soporte desde el 14/10/2025, deja de venir marcado por defecto.
- Comprobar fuentes ya no falla por Windows: informa que se crea al armar el pendrive.
- **Acceso controlado a carpetas.** En la primera instalación real, Ventoy borró las particiones del Kingston, pero las tres escrituras de formato recibieron `ErrCode:5`. Defender registró el evento 1127: el Acceso controlado a carpetas impidió que Ventoy2Disk.exe modificara `\Device\Harddisk1\DR12`. Ahora:
  - antes de pedir la confirmación, RESCUSB lee `Get-MpPreference`. Si la protección está en modo 1 o 3 y Ventoy no figura como permitido, se detiene, abre Seguridad de Windows, copia la ruta y espera; con 0 vuelve sin borrar;
  - Ventoy se extrae siempre en `estado\ventoy-instalador`, de nuevo y verificado en cada corrida, para que la excepción se mantenga;
  - si igual aparece `ErrCode:5`, el error lo explica como un bloqueo de escritura de Windows;
  - la confirmación pasó a voseo y con tildes, y una unidad sin letra se muestra como «Sin letra asignada».
- **Reconexión del pendrive.** En la prueba real, el Kingston desapareció de Windows mientras se creaba Windows 11 y el programa volvía al menú. Ahora, antes del borrado, RESCUSB avisa, espera a que lo vuelvas a conectar y lo reconoce aunque cambie el número de disco. Exige que coincidan modelo, capacidad, las dos series, el identificador PNP y la ruta; nunca adopta otro dispositivo.

Las pruebas nuevas cubren:

- que la búsqueda solo lea la página pública de Microsoft;
- la preferencia por el hash publicado;
- la aceptación por firma, también sin Internet;
- la exigencia de firma: un binario firmado por Microsoft se acepta y uno sin firma se rechaza;
- la arquitectura, el idioma y la versión de la imagen;
- el nombre y la marca de la copia;
- Enter abre la herramienta y el armado se completa;
- el pendrive reconectado se reconoce con otro número de disco y nunca se confunde con otro.

Se descargaron de verdad las dos herramientas (21.591.048 y 19.463.448 bytes, desde `download.microsoft.com`) y su firma se validó. La herramienta de Windows 11 se abrió en una preparación real y empezó a descargar Windows.

**Verificado con una ISO real:** la herramienta generó `Windows.iso` (7.236.550.656 bytes, Windows 11 en español, x64). RESCUSB la montó, validó la firma de Microsoft de los dos `setup.exe` y, con DISM, la arquitectura, el idioma y la versión. La aceptó como `windows11-herramienta-es-ES-2f7deb7b.iso`. En las pruebas automáticas, el montaje y DISM se siguen simulando.
## Cambios de 2.0.3
Corrigen lo que apareció al probar el armado real con el Kingston: Microsoft rechazó Windows 10 y 11 y el programa quedaba sin salida, la consulta de fuentes llenaba la pantalla de barras de curl y el encabezado se desordenaba.

- **Windows pendiente en lugar de bloqueo total.** Si faltan fuentes y Ventoy está disponible, RESCUSB muestra qué falta y ofrece: preparar ahora lo disponible, abrir la página oficial de Microsoft para bajar la ISO desde el navegador o volver a comprobar. Nada se borra antes de esa elección. Lo omitido queda en `pending` del estado, el pendrive **nunca** se marca LISTO y **Continuar** vuelve a intentarlo sin reinstalar Ventoy. Dos pruebas nuevas cubren ambos tramos: cinco herramientas preparadas con Windows pendiente y la reanudación que lo completa.
- **ISO bajada desde el navegador.** La búsqueda local suma la carpeta Descargas real de Windows (la carpeta conocida del registro), además de la del perfil. La ISO se sigue aceptando solo si coincide con el SHA-256 publicado por Microsoft para el idioma elegido.
- **Consulta de fuentes silenciosa.** La lectura de hashes y metadatos usa curl sin barra de progreso; las barras quedan solo para las descargas reales de imágenes.
- **Ventana de trabajo estable.** En la ventana propia de RESCUSB se desactiva el modo de edición rápida: un clic ya no congela la salida en «Seleccionar» ni la reacomoda al cambiar de tamaño. La ventana se fija en 90 columnas. Una consola que el usuario ya tenía abierta (modos de diagnóstico) no se toca.

Se repitió la consulta real de fuentes: las seis publicaciones fijadas siguen correctas, sin barras de progreso, y Microsoft volvió a rechazar Windows 10 y 11. El aviso nuevo se comprobó en una consola real de Windows con PowerShell 5.1.

- Rechazo de discos internos/fijos, sistema, arranque, paginación, ubicación del programa, capacidad inesperada, estado no saludable, identidad incompleta o duplicada.
- Selección por posición en una lista filtrada: nunca por un número físico arbitrario. Cambios de identidad se rechazan al volver a consultar el dispositivo. La desconexión/reconexión dejó de ser un paso obligatorio.
- Confirmación exacta con serie legible, conservando los valores originales para verificar identidad. No se aceptan un sí genérico, una serie ajena o caracteres invisibles que el usuario no puede escribir.
- Estructura Ventoy, asignación letra-disco, parámetros CLI, confirmación y `cli_done` probados con un instalador simulado. La reanudación no reinstala Ventoy.
- Descargas interrumpidas, parciales completos, reuso, corrupción, cuarentena, falta de espacio, cambio de dispositivo, copia local reanudable y extracción controlada de Memtest86+.
- Reconocimiento ISO9660 y UDF, incluido UDF sin ISO9660, secuencias incompletas y rechazo de HTML como imagen. Siempre se mantiene el hash esperado como condición independiente.
- Rutas OneDrive con las 16 etiquetas Cloud Files, directorios normales, rutas no creadas y junction real rechazada sin tocar su destino.
- Descubrimiento dinámico de edición, hash por idioma/x64, nomenclaturas antiguas y actuales de las ISO Microsoft, exclusión de ARM/x86, hosts falsos, ambigüedad, rechazo de servicio y fallo de red.
- Búsqueda de Windows con respuestas simuladas: solo se lee la página pública de Microsoft y nunca se piden enlaces de descarga.
- Flujo completo de las siete herramientas simulado: si falla Windows en la comprobación previa, no se invoca el instalador ni se escribe en el USB; si termina el contenido elegido, se marca completo; si hay un fallo, se marca parcial.
- Inicio de una sola ventana comprobado en la estructura del lanzador: no espera dejando el BAT anterior abierto, no repite elevación en la app y no deja otra pausa final en el BAT. El menú vuelve dentro de la misma sesión.

Las pruebas crean archivos pequeños y enlaces temporales propios dentro de tests/. No usan Internet, no consultan almacenamiento físico ni ejecutan Ventoy real. Pueden mostrar datos y mensajes de un USB ficticio durante las simulaciones.

## Revalidación y correcciones de 2.0.1–2.0.2

Se revisó la copia entregada y coincidieron los 30 archivos originales con sus fuentes. La suite anterior volvió a pasar, pero seis casos nuevos reprodujeron defectos adicionales: 0 aprobados / 6 fallos antes de corregirlos, 6 aprobados / 0 fallos después.

- **Integridad final:** la última lectura ahora compara el SHA-256 con el valor esperado; antes solo lo calculaba. Una corrupción detectada después de las verificaciones previas produce FALLO y retira la ISO del menú mediante cuarentena. Para Memtest se conserva el hash del contenido del ZIP verificado como referencia independiente.
- **Reanudación tras corrupción:** una descarga terminada con tamaño, hash o formato incorrecto se conserva con otro nombre. El próximo intento empieza limpio y no queda atascado reanudando un archivo completo inválido. Los parciales de transferencias interrumpidas se siguen conservando para HTTP Range.
- **Espacio al reutilizar:** un .part completo y verificado puede renombrarse sin reservar espacio para descargarlo otra vez. Una ISO local ya copiada y verificada tampoco exige espacio para una segunda copia.
- **Configuración:** se rechazan herramientas duplicadas para que el total anunciado coincida con las herramientas realmente seleccionadas.
- **Inicio desde PowerShell 7:** ejecutar PRUEBAS.bat mediante un proceso CMD que heredaba las rutas de módulos de PowerShell 7 reprodujo la ausencia de Get-FileHash en Windows PowerShell 5.1. Los tres BAT fijan ahora la ruta de módulos del Windows PowerShell del sistema dentro de su ámbito local. Así evitan esa mezcla de versiones y no cambian variables persistentes del usuario.

La misma ejecución mediante CMD pasó después las tres suites: **69 + 20 + 6 = 95 pruebas**, sin errores en stderr. La vista del BAT y el diagnóstico real de solo lectura reconocieron únicamente el Kingston compatible, sin mostrar discos internos.

En la nueva consulta de red, Ventoy, SystemRescue, Memtest86+, Hiren, Rescuezilla y Ubuntu mantuvieron sus hashes oficiales y devolvieron HTTP 200 a la consulta HEAD. Los tamaños anunciados están dentro de los presupuestos. Windows 10 y Windows 11 devolvieron rechazo de sesión de Microsoft: **el paquete completo de siete herramientas todavía no puede confirmarse disponible** desde esta conexión. No se repitieron consultas para eludir ese rechazo.

Se repitió una reanudación HTTP real de Memtest desde un archivo nuevo de 1.024 bytes: ZIP final de 6.593.407 bytes e ISO de 20.207.616 bytes, con SHA-256 correcto. Se volvió a verificar el ZIP de Ventoy sin ejecutarlo. La CLI y sus parámetros se contrastaron con la [documentación de Ventoy](https://www.ventoy.net/en/doc_windows_cli.html); el requisito de curl 8.4 se contrastó con su [manual oficial](https://curl.se/docs/manpage.html#--max-filesize).

## Comprobaciones reales realizadas

- Se reprodujo y corrigió el rechazo de la carpeta real de OneDrive: etiqueta Cloud Files 0x9000E01A. El BAT y la escritura atómica de estado funcionan desde esa ruta.
- El diagnóstico de solo lectura reconoció el Kingston de 61,99 GB / 57,73 GiB y la lista filtrada mostró únicamente ese pendrive. Los discos principales quedaron fuera.
- El modo Fuentes contrastó las seis publicaciones de SHA-256 de Ventoy, SystemRescue, Memtest86+, Hiren, Rescuezilla y Ubuntu.
- Se descargó realmente Memtest86+ 8.10 x86_64 GRUB: ZIP de 6.593.407 bytes, hash oficial correcto; ISO extraída de 20.207.616 bytes, SHA-256 `4edc7bc982a71642a595ce97fd8affb1769cb3019fa2822d0fe095554ffb198d`. Se completó también una reanudación HTTP Range real desde un parcial de 1.024 bytes.
- Se descargó y verificó el ZIP oficial de Ventoy 1.1.18, de 16.680.699 bytes, y se comprobó su estructura. **El ejecutable no se inició**.
- Se leyeron las páginas y hashes oficiales de Windows 10 y 11, se obtuvo una sesión normal de descarga y se observaron enlaces x64 generados por Microsoft. En consultas posteriores el proveedor devolvió rechazos de sesión. El resolutor respeta esos rechazos y el flujo simulado verifica que bloquean la preparación antes del borrado. No se afirma disponibilidad continua de un servicio externo.
- La vista del menú se ejecutó con PowerShell 5.1; muestra la identidad RESCUSB, explicación breve, acciones con nombres claros y el paquete completo predeterminado. El aviso UAC del sistema no se elimina.
- La imagen de identidad se inspeccionó visualmente: 1200 × 630, 37.377 bytes. El HTML y los archivos de autoría son locales; no se publicó una web ni se afirma indexación.
- La ficha local y su página 404 se probaron en el navegador a 1280 y 320 píxeles: sin desborde horizontal ni imágenes rotas, enlaces de acción de al menos 44 píxeles y regreso correcto desde 404. El servidor temporal se cerró después de la revisión.
- La auditoría estática del kit revisó títulos, descripciones, favicon, peso de imágenes y enlaces locales. El aviso heurístico sobre el retorno de 404 no aplica: el enlace local a index.html se comprobó en el navegador. El copyright conserva el año de esta versión.

## Lo que sigue pendiente

No se formateó ni se escribió ningún pendrive durante el desarrollo. Quedan pendientes la instalación real de Ventoy, detección de sus volúmenes después de formatear, descarga íntegra de las ISO grandes sobre ese USB y arranque físico de las imágenes en equipos Legacy/UEFI y sus configuraciones de Secure Boot.

No se descargaron completas las ISO de Windows, SystemRescue, Hiren, Rescuezilla ni Ubuntu. La obtención de metadatos, enlaces y hashes no equivale a verificar todos los bytes de esas imágenes. RESCUSB solo marca LISTO cuando el usuario ejecuta el flujo y todas las imágenes elegidas terminan correctamente. El campo `bootTested` permanece en false porque no representa una prueba física.

Una sola ventana significa una sola ventana de trabajo después de aceptar permisos. La transición UAC depende de Windows y no se automatizó una aceptación del aviso. La instalación por CLI usa el proceso de Ventoy en segundo plano, pero su ejecución real sigue pendiente de la confirmación del usuario.

Los archivos del kit SEO están incluidos y validados localmente. Canonical, URLs públicas de imágenes, sitemap con URLs reales, HTTP/404 servido, indexabilidad e indexación requieren una publicación futura separada.
