# DKR-04: políticas TWA del Dockerfile, con Conftest (OPA). Cada regla tiene un id (TWA-DOCKER-NN) que aparece en el
# mensaje; un repo la exceptúa en params.exceptions de DKR-04 de su .twa-standards.yml, con la razón.
#
# Conftest entrega el Dockerfile como una lista de instrucciones {Cmd, Value, Flags, Stage}; la imagen que se publica
# es la de la última etapa (stage).
package main

import rego.v1

# Las instrucciones, sea cual sea la forma en que las entregue conftest (una lista o una lista de listas)
instructions := [i | some x in input; is_object(x); i := x] if {
	some x in input
	is_object(x)
} else := [i | some l in input; is_array(l); some i in l]

final_stage := max({i.Stage | some i in instructions; i.Cmd == "from"})

final := [i | some i in instructions; i.Stage == final_stage]

# Las excepciones del repo llegan como datos (--data): {"twa": {"exceptions": ["TWA-DOCKER-03"]}}
excepted(id) if id in data.twa.exceptions

# Imagen base de la etapa final: el JRE de eclipse-temurin (tag con versión, con o sin digest)
final_from := [i | some i in final; i.Cmd == "from"][0]

final_image := lower(final_from.Value[0])

deny contains msg if {
	not excepted("TWA-DOCKER-01")
	not regex.match(`^(docker\.io/(library/)?)?eclipse-temurin:[0-9]+(\.[0-9.+_]+)?-jre[a-z0-9.-]*(@sha256:[a-f0-9]{64})?$`, final_image)
	msg := sprintf("TWA-DOCKER-01: la imagen final parte de %s; tiene que ser el JRE de eclipse-temurin (eclipse-temurin:<versión>-jre)", [final_from.Value[0]])
}

# Usuario sin privilegios: el último USER de la etapa final existe y no es root
final_users := [i.Value[0] | some i in final; i.Cmd == "user"]

deny contains "TWA-DOCKER-02: la etapa final no tiene USER: el proceso corre como root" if {
	not excepted("TWA-DOCKER-02")
	count(final_users) == 0
}

deny contains msg if {
	not excepted("TWA-DOCKER-02")
	count(final_users) > 0
	user := final_users[count(final_users) - 1]
	regex.match(`^(root|0)(:.*)?$`, lower(user))
	msg := sprintf("TWA-DOCKER-02: el USER final es %s: el proceso corre como root", [user])
}

# HEALTHCHECK en la etapa final (y no NONE)
final_healthchecks := [i | some i in final; i.Cmd == "healthcheck"]

deny contains "TWA-DOCKER-03: la etapa final no tiene HEALTHCHECK" if {
	not excepted("TWA-DOCKER-03")
	count(final_healthchecks) == 0
}

deny contains "TWA-DOCKER-03: HEALTHCHECK NONE apaga el chequeo de salud" if {
	not excepted("TWA-DOCKER-03")
	some h in final_healthchecks
	upper(h.Value[0]) == "NONE"
}

# Sin secretos en la imagen: ni ENV ni ARG con nombre de credencial, ni copiar archivos de credenciales. Un secreto del
# build entra con RUN --mount=type=secret (como el settings.xml de Maven) y no queda en ninguna capa
secret_name := `(?i)(password|passwd|secret|token|api_?key|private_?key|credential|access_?key)`

secret_file := `(?i)(settings\.xml|\.npmrc|\.netrc|\.m2(/|$)|id_rsa|id_ed25519|\.pem$|\.p12$|\.jks$|\.env$|credentials)`

deny contains msg if {
	not excepted("TWA-DOCKER-04")
	some i in instructions
	i.Cmd in {"env", "arg"}
	name := split(i.Value[0], "=")[0]
	regex.match(secret_name, name)
	msg := sprintf("TWA-DOCKER-04: %s %s parece una credencial: queda en la imagen. Usar RUN --mount=type=secret", [upper(i.Cmd), name])
}

deny contains msg if {
	not excepted("TWA-DOCKER-04")
	some i in instructions
	i.Cmd in {"copy", "add"}
	count(i.Value) > 1
	some src in array.slice(i.Value, 0, count(i.Value) - 1)
	regex.match(secret_file, src)
	msg := sprintf("TWA-DOCKER-04: %s %s copia un archivo de credenciales a la imagen. Usar RUN --mount=type=secret", [upper(i.Cmd), src])
}
