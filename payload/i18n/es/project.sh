# shellcheck shell=bash disable=SC2034,SC2154
# FEAT-045 T3: lo que imprime `biab-project` (payload/scripts/biab-project). Los códigos de
# salida, el prefijo `biab-project:` y las palabras que imprime `status` (scaffold, init,
# register...) son el contrato que leen las skills y no se traducen. Es la gemela de
# ../en/project.sh: mismas claves, mismos %s.
BIB_MSG[project.err.usage]='uso: biab-project list [--all] | scaffold <plantilla|idea> <proyecto> | status <proyecto> | progress get | progress set <plantilla|idea> <proyecto>'
BIB_MSG[project.err.source_missing]='falta el origen de la plantilla: %s'
BIB_MSG[project.err.bad_catalogue]='catálogo no válido: %s'
BIB_MSG[project.err.bad_catalogue_symlink]='catálogo no válido: enlace simbólico en el origen de la plantilla: %s'
BIB_MSG[project.err.cannot_write]='no se puede escribir en: %s'
BIB_MSG[project.err.home_unset]='no se puede escribir en: $HOME no está definido'
BIB_MSG[project.err.would_overwrite]='se sobrescribiría: %s'
BIB_MSG[project.err.invalid_name]='nombre de proyecto no válido: %s'
BIB_MSG[project.err.unknown_template]='plantilla desconocida: %s'
BIB_MSG[project.err.name_in_use]='el nombre ya está en uso: %s'
BIB_MSG[project.err.no_progress]='aún no hay progreso'
BIB_MSG[project.err.corrupt_progress]='archivo de progreso dañado: %s'
BIB_MSG[project.out.created]='creado %s\n'
BIB_MSG[project.out.unchanged]='sin cambios %s\n'
