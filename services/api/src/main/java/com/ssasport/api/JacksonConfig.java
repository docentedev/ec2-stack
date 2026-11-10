package com.ssasport.api;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Configuracion Jackson del api.
 * En Spring Boot 4 el auto-config del ObjectMapper no se activo automaticamente
 * con los starters agregados (ver diagnóstico del build); se define bean explicito.
 */
@Configuration
public class JacksonConfig {

    @Bean
    public ObjectMapper objectMapper() {
        return new ObjectMapper();
    }
}
