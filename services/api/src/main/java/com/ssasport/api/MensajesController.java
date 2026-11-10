package com.ssasport.api;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.ScanRequest;

/**
 * Devuelve los ultimos N mensajes (por defecto 10) guardados en cada tabla
 * DynamoDB (pagos, notificaciones, analiticas).
 *
 *   GET /mensajes            -> 10 por tabla
 *   GET /mensajes?limit=5    -> 5 por tabla (maximo 50)
 *
 * Las tablas solo tienen PK (sin clave de orden), por lo que se hace Scan y se
 * ordena por el atributo "fecha" descendente. Suficiente para el volumen del
 * proyecto; para tablas grandes habria que agregar un indice (GSI) por fecha.
 */
@RestController
public class MensajesController {

    private static final int MAX_LIMIT = 50;

    private final DynamoDbClient dynamo;
    private final ObjectMapper objectMapper;
    private final List<String> tablas;

    public MensajesController(ObjectMapper objectMapper,
                              @Value("${app.dynamodb.region}") String region,
                              @Value("${app.mensajes.tablas}") List<String> tablas) {
        this.objectMapper = objectMapper;
        this.tablas = tablas;
        this.dynamo = DynamoDbClient.builder().region(Region.of(region)).build();
    }

    @GetMapping("/mensajes")
    public Map<String, Object> mensajes(@RequestParam(defaultValue = "10") int limit) {
        int n = Math.max(1, Math.min(limit, MAX_LIMIT));
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("limit", n);
        for (String tabla : tablas) {
            response.put(tabla, ultimos(tabla, n));
        }
        return response;
    }

    private Object ultimos(String tabla, int n) {
        try {
            List<Map<String, AttributeValue>> items = new ArrayList<>();
            dynamo.scanPaginator(ScanRequest.builder().tableName(tabla).build())
                    .forEach(page -> items.addAll(page.items()));

            return items.stream()
                    .sorted(Comparator.comparing((Map<String, AttributeValue> i) -> str(i, "fecha")).reversed())
                    .limit(n)
                    .map(this::toMap)
                    .toList();
        } catch (Exception e) {
            // una tabla caida/sin permisos no tumba el resto de la respuesta
            return Map.of("error", String.valueOf(e.getMessage()));
        }
    }

    private Map<String, Object> toMap(Map<String, AttributeValue> item) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("pk", str(item, "PK"));
        m.put("fecha", str(item, "fecha"));
        m.put("origen", str(item, "origen"));
        // "mensaje" es el JSON publicado por la api: se extrae el texto si se puede
        String raw = str(item, "mensaje");
        try {
            JsonNode node = objectMapper.readTree(raw);
            m.put("mensaje", node.hasNonNull("mensaje") ? node.get("mensaje").asText() : raw);
        } catch (Exception e) {
            m.put("mensaje", raw);
        }
        return m;
    }

    private static String str(Map<String, AttributeValue> item, String key) {
        AttributeValue v = item.get(key);
        return v == null || v.s() == null ? "" : v.s();
    }
}
