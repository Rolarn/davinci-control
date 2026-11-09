# Идемпотентно: правка считается сделанной, если старое значение заменено ИЛИ новое уже стоит.
# a = узел CPULittleClusterMinFreq (список Values), b = хинт INTERACTION, c = хинт EXPENSIVE_RENDERING/GPUMinFreq
/"Name": "CPULittleClusterMinFreq"/ { innode = 1 }
innode && /"(1248000|1017600)"/ { sub(/"1248000"/, "\"1017600\""); innode = 0; a = 1 }
innode && /\]/ { innode = 0 }
/"PowerHint":/ { ph = $0; act = 0 }
ph ~ /"INTERACTION"/ && /"Node": "CPULittleClusterMinFreq"/ { act = 1 }
ph ~ /"EXPENSIVE_RENDERING"/ && /"Node": "GPUMinFreq"/ { act = 2 }
act == 1 && /"Value": "(1248000|1017600)"/ { sub(/"1248000"/, "\"1017600\""); act = 0; b = 1 }
act == 2 && /"Value": "(0|7)"/ { sub(/"0"/, "\"7\""); act = 0; c = 1 }
{ print }
END { print a + b + c > "/dev/stderr" }
