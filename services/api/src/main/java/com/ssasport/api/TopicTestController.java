package com.ssasport.api;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.TimeUnit;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Endpoint de prueba del flujo kafka: publica un mensaje en el topico "pagos"
 * y responde con la confirmacion (particion/offset).
 *
 *   GET /topic-test?msj=test
 *
 * Los 3 consumers (grupos analiticas/notificaciones/pagos) reciben una copia
 * del mensaje (fan-out) y lo loguean en consola.
 */
@RestController
public class TopicTestController {

    static final String TOPIC = "pagos";

    private final KafkaTemplate<String, String> kafkaTemplate;
    private final ObjectMapper objectMapper;

    public TopicTestController(KafkaTemplate<String, String> kafkaTemplate, ObjectMapper objectMapper) {
        this.kafkaTemplate = kafkaTemplate;
        this.objectMapper = objectMapper;
    }

    @GetMapping("/topic-test")
    public Map<String, Object> topicTest(@RequestParam(defaultValue = "test") String msj) throws Exception {
        // payload JSON con metadatos (formato acordado, ver README)
        Map<String, String> payload = Map.of(
                "mensaje", msj,
                "origen", "api",
                "fecha", Instant.now().toString());
        String json = objectMapper.writeValueAsString(payload);

        // envio sincronico (con timeout) para poder responder con particion/offset
        SendResult<String, String> result = kafkaTemplate.send(TOPIC, json).get(10, TimeUnit.SECONDS);

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("status", "enviado");
        response.put("topico", TOPIC);
        response.put("particion", result.getRecordMetadata().partition());
        response.put("offset", result.getRecordMetadata().offset());
        response.put("mensaje", msj);
        return response;
    }
}
