![RESCUSB | Rodolfo Agustín García](assets/og-image.png)

# RESCUSB

**Tu pendrive de rescate. Preparado para cuando algo falla.**

RESCUSB convierte un pendrive de 64 GB en una caja de herramientas de rescate: instala Ventoy, obtiene las imágenes oficiales, descarga o copia lo necesario y verifica cada archivo. Todo se maneja desde una sola ventana de terminal.

## Empezar

1. Descargá RESCUSB desde [GitHub](https://github.com/ragustingarcia/RESCUSB) (**Code → Download ZIP**) y descomprimilo en una carpeta del disco del PC. No ejecutes el programa desde el pendrive que vas a preparar.
2. Conectá el pendrive y abrí **INICIAR.bat**. Aceptá el permiso de administrador de Windows si aparece.
3. Elegí **Armar mi pendrive completo**. La opción predeterminada incluye las siete herramientas.
4. Elegí tu pendrive en la lista. Los discos internos y los discos USB fijos no se ofrecen. **Dejalo conectado** durante todo el proceso.
5. RESCUSB comprueba las fuentes oficiales y obtiene automáticamente los enlaces y SHA-256 de Windows. Todavía no se borra el USB. Si alguna fuente no responde, podés preparar ahora lo disponible y agregar el resto después con **Continuar**.
6. Revisá el modelo, la capacidad, la unidad y la serie. Para autorizar el borrado, escribí **BORRAR seguido de la serie** que muestra el programa.
7. Esperá mientras se instala Ventoy y se descargan/verifican las imágenes directamente en el USB. Si se interrumpe, elegí **Continuar** la próxima vez.
8. Cuando aparezca **LISTO**, expulsá el pendrive desde Windows. Al reiniciar el equipo, elegilo desde el menú de arranque.

La preparación elimina todas las particiones y archivos del pendrive elegido. La consulta de fuentes ocurre antes de ese borrado. Si una fuente necesaria no está disponible, RESCUSB conserva el USB, explica qué falta y te deja elegir: preparar ahora lo disponible, descargar la ISO de Windows desde el navegador o volver al menú. Nunca presenta un resultado incompleto como terminado.

## El menú

| Opción | Para qué sirve |
|---|---|
| **Armar mi pendrive completo** | Primera preparación. Comprueba fuentes, solicita confirmación, instala Ventoy y prepara el contenido. |
| **Continuar o completar mi pendrive** | Reconoce un USB creado por este programa, conserva Ventoy y retoma/completa descargas. |
| **Comprobar que todo esté disponible** | Consulta el USB y las fuentes, incluidos los enlaces y hashes de Windows. No borra ni instala. |
| **Ajustes y contenido** | Cambia el idioma de Windows o elige herramientas con números. Todas vienen seleccionadas por defecto. |
| **Qué hace RESCUSB** | Explica las herramientas y cómo arrancar el pendrive, dentro de la misma terminal. |

El BAT abre PowerShell automáticamente. Si necesita elevar permisos, cierra la ventana de inicio y deja una sola ventana de trabajo. El aviso de seguridad de Windows pertenece al sistema y no se suprime. Si ya se inició como administrador, se usa la misma ventana.

## Qué queda en el USB

| Herramienta | Uso principal |
|---|---|
| SystemRescue | Recuperar archivos y reparar particiones. |
| Memtest86+ | Comprobar la memoria RAM. |
| Hiren's BootCD PE | Herramientas de reparación en un entorno Windows PE. |
| Rescuezilla | Crear y restaurar copias de discos. |
| Ubuntu Desktop Live | Usar Linux sin instalarlo y acceder a archivos. |
| Windows 11 x64 | Reparar o reinstalar Windows 11. |
| Windows 10 x64 | Reparar o reinstalar Windows 10. |

Windows viene configurado en **español y x64**. En Ajustes podés elegir español de Latinoamérica o inglés. Las imágenes de Windows son de consumo y multiedición; no son versiones Enterprise de evaluación ni un Windows portátil. La activación/licencia del equipo sigue siendo independiente de RESCUSB.

## Windows automático y fuentes oficiales

RESCUSB lee la página pública de Microsoft, descubre la edición vigente, el idioma y su hash publicado, inicializa una sesión normal de descarga y solicita un enlace nuevo. **No hace falta pegar enlaces ni escribir hashes.** Los enlaces firmados quedan en memoria, no en el programa, el ZIP ni los informes. No se ejecuta JavaScript remoto, Fido, Rufus ni código descargado para generar esos enlaces.

El flujo de la página de Microsoft puede cambiar y el servicio puede rechazar solicitudes o no estar disponible. RESCUSB respeta ese rechazo y detiene la preparación antes del borrado. No cambia de IP, no resuelve desafíos ni usa copias de terceros. Una comprobación de metadatos correcta tampoco obliga al servidor a mantener disponible la descarga durante horas; si falla después, el parcial se conserva para Continuar.

También busca automáticamente ISO de Windows en **ISO-OFICIALES** junto al programa y en la carpeta **Downloads/Descargas** habitual del perfil. Solo revisa archivos ISO de Windows en esas carpetas, sin recorrer subcarpetas ni modificar los originales. Usa una copia local únicamente si coincide con el **SHA-256 oficial actual del idioma elegido** y tiene formato ISO válido. Así puede reutilizar una descarga oficial existente. Una ISO hecha por Media Creation Tool con un hash distinto no se acepta por aproximación.

Los otros proyectos usan versiones fijadas en `catalogo.json`, publicadas y verificadas por sus fuentes oficiales. Sus hashes se contrastan otra vez durante la comprobación. Un cambio de versión/hash no se acepta silenciosamente. Ver [FUENTES.md](FUENTES.md).

## Requisitos y espacio

- Windows 10/11 x64 Intel/AMD, PowerShell 5.1 y permiso de administrador para preparar el USB.
- `curl.exe` integrado en Windows, versión 8.4.0 o posterior. RESCUSB lo comprueba y no instala componentes del sistema por su cuenta.
- Internet y un pendrive que Windows identifique como USB extraíble. Para este proyecto se admite capacidad física de 48 a 72 GB decimales, correspondiente al USB nominal de 64 GB solicitado.
- Un USB de 64 GB comerciales suele aparecer como unos 59,6 GiB; algunos modelos tienen otra capacidad real. El Kingston comprobado informa 61,99 GB / 57,73 GiB.
- El presupuesto conservador del contenido es de unos 36 GiB más 2 GiB de reserva y un margen pequeño para extraer Memtest86+. El tamaño real depende de las imágenes oficiales. Se comprueba espacio antes de cada transferencia.

Una partición de 32 GB puede ser solo parte de un dispositivo mayor. Ventoy crea nuevamente las particiones usando la capacidad física informada por Windows. RESCUSB no puede recuperar una capacidad que el controlador no expone ni detectar por sí solo memoria falsificada o sectores defectuosos.

## Reanudación y resultado

Las descargas usan HTTP Range y archivos **.part**. Solo se renombran a **.iso** tras validar tamaño, SHA-256 y formato. Las ISO finales se vuelven a leer para verificar su integridad. Las copias locales de Windows usan Robocopy reanudable; su carpeta temporal se oculta del menú de Ventoy con `.ventoyignore`.

Conservá la carpeta del programa, incluido **estado**. Allí quedan la configuración, los hashes esperados, la identidad del USB y los informes. Los nombres de Windows incorporan parte de su hash para conservar imágenes y parciales anteriores cuando Microsoft cambia de versión.

En el pendrive quedan **ISO**, el identificador de dispositivo, **informe-rescate.json**, **RESCUSB-ESTADO.json** y **RESCUSB-LEEME.txt**. El estado completo solo se marca después de que todas las herramientas elegidas terminaron correctamente. Antes de escribir contenido nuevo, la marca se establece como preparación en curso para no conservar un “listo” antiguo.

## Si algo se interrumpe

| Situación | Cómo seguir |
|---|---|
| Otra sesión abierta | Cerrá las ventanas de versiones anteriores y volvé a abrir INICIAR.bat. No cierres un instalador que esté trabajando. |
| El pendrive no aparece | Debe ser USB extraíble, tener identidad fiable, estado saludable y capacidad compatible. No hay una opción para forzar discos internos o USB fijos. |
| Microsoft rechaza la sesión | No se borra el USB durante la comprobación. RESCUSB ofrece tres caminos: **preparar ahora** las herramientas disponibles y dejar Windows pendiente para **Continuar**; **abrir la página oficial** para bajar la ISO desde el navegador (queda en Descargas y se reconoce por su SHA-256); o **volver a comprobar** más tarde. En Windows, la página de Windows 10 puede ofrecer solo la herramienta de creación de medios, cuya ISO tiene otro hash y no se acepta. |
| Descarga interrumpida | Conservá los .part y elegí Continuar. |
| Servidor sin soporte Range / curl 33 o 416 | Revisá el nombre del parcial afectado. Si decidís empezar de cero, renombrá solo ese .part a una extensión distinta y reintentá. Seguirá ocupando espacio hasta que lo retires. |
| Hash incorrecto | Un archivo completo que falla la verificación, sea .part o ISO final, se conserva con extensión .invalid-…part. Continuar puede iniciar una descarga limpia sin reutilizar ese archivo. La cuarentena sigue ocupando espacio. Revisá el informe y el USB si vuelve a ocurrir. |
| Espacio insuficiente | Elegí menos herramientas desde Ajustes o liberá archivos conocidos. No se borra contenido automáticamente para hacer lugar. |
| Ventoy falla o no confirma en 10 minutos | Revisá estado/tools-…/cli_log.txt y el proceso Ventoy. No inicies otro preparador ni desconectes el USB mientras el instalador siga activo. No se mata ni se reintenta automáticamente un formateador en curso. |
| Falta la marca de identidad | Continuar no adopta automáticamente un USB ajeno o una instalación interrumpida. Revisá los logs antes de decidir si repetís una preparación que vuelva a borrarlo. |

## BIOS, UEFI y Secure Boot

Ventoy se instala en MBR con una partición de datos exFAT y su partición VTOYEFI. Proporciona el menú de arranque Legacy/UEFI; cada imagen mantiene sus requisitos de arquitectura y hardware. Elegí la entrada UEFI o Legacy que corresponda en el firmware del equipo.

El soporte de Secure Boot de Ventoy está activado por defecto y puede requerir registrar su clave. RESCUSB no cambia el firmware ni registra claves del PC. Memtest86+ advierte que su binario no está firmado por Microsoft. Consultá las guías oficiales de [FUENTES.md](FUENTES.md). Para algunas imágenes pequeñas, Ventoy ofrece Ctrl+D / Memdisk si el modo normal falla.

La descarga verificada no sustituye una prueba de arranque real. El informe distingue contenido preparado de arranque probado: **bootTested queda en false** hasta una validación física independiente.

## Seguridad del dispositivo

Se usan bus USB, evidencia CIM, medio extraíble, modelo, dos series, identificador PNP, ruta, firma, tamaño y exclusión de sistema/arranque/paginación/ubicación del programa. Se rechazan identidades duplicadas. Solo se ofrece la lista filtrada y se vuelve a comprobar el dispositivo antes de las operaciones. La desconexión/reconexión obligatoria de la versión anterior se reemplazó por estos controles y una confirmación visible con la serie.

La CLI de Ventoy necesita un número de disco físico y no ofrece un bloqueo de identidad atómico para toda la operación. Por eso, después de confirmar **no intercambies dispositivos**. No existe un modo de borrado sin confirmación. Los hashes se verifican contra publicaciones oficiales por HTTPS; no se implementa verificación GPG ni protección contra un compromiso de las propias fuentes.

## Diagnóstico y pruebas

- **INICIAR.bat /diagnostico**: programa, rutas, OneDrive, estado y pendrives; sin red ni instalación.
- **INICIAR.bat /fuentes**: fuentes y enlaces/hashes automáticos de Windows; no descarga ISO ni instala Ventoy.
- **INICIAR.bat /vista**: muestra el menú sin consultar dispositivos ni elevar permisos.
- **PRUEBAS.bat**: pruebas de seguridad y del flujo completo con archivos pequeños, proveedores y dispositivos simulados. No necesita Internet ni ejecuta el instalador real. Puede mostrar mensajes de confirmación de un USB ficticio.
- [VALIDACION.md](VALIDACION.md): resultados y alcance real de las pruebas.

## Identidad, autoría y publicación

Hecho por **[Rodolfo Agustín García](https://ragustingarcia.com/)**.

El kit de autoría incluye metadatos SoftwareApplication/Person, Open Graph/Twitter, imagen propia, favicon, humans.txt, robots.txt, ai.txt, llms.txt, sitemap y una ficha HTML local. El código está publicado en **[github.com/ragustingarcia/RESCUSB](https://github.com/ragustingarcia/RESCUSB)**. RESCUSB todavía no tiene web propia ni ficha de tienda: no se inventan esos enlaces ni se afirma indexación. El detalle está en [SEO-Y-AUTORIA.md](SEO-Y-AUTORIA.md).

## Licencia

RESCUSB es software propietario de Rodolfo Agustín García: podés descargarlo y usarlo sin cargo para preparar pendrives, pero no redistribuirlo, modificarlo para publicarlo ni venderlo. Ver [LICENSE](LICENSE). Las imágenes y herramientas que descarga pertenecen a sus respectivos proyectos y conservan sus propias condiciones; RESCUSB no las incluye ni las redistribuye.
