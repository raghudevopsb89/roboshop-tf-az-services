package com.roboshop.shipping;

import com.roboshop.shipping.model.City;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.Arrays;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

/**
 * Component integration test for the Shipping service.
 *
 * <p>Boots the full Spring context against a real MySQL provided by Testcontainers and
 * wired into the context via {@link ServiceConnection} (Spring Boot 3.1+). The database is
 * populated by the application's own {@code schema.sql} + {@code data.sql} (spring.sql.init,
 * {@code mode=always}), so this exercises the real JPA mapping of {@link City}, the real
 * {@code cities} seed data, and BigDecimal latitude/longitude handling end to end over HTTP.
 *
 * <p>NOTE: {@code spring.jpa.hibernate.ddl-auto} is overridden to {@code none} for the test.
 * In production the property is {@code validate} and the {@code cities} table already exists
 * in the external MySQL; on a fresh container the table is created by {@code schema.sql}
 * (which runs after Hibernate because {@code defer-datasource-initialization=true}), so
 * {@code validate} would fail against the not-yet-created table. {@code none} lets the init
 * scripts create + seed the schema, which is what we want to assert against.
 *
 * <p>These tests were NOT executed locally (no JRE on the authoring machine). They are written
 * to compile and run under CI (self-hosted runner with Docker + JDK 17) via {@code mvn verify}.
 */
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "spring.jpa.hibernate.ddl-auto=none"
)
@Testcontainers
class ShippingCityRepositoryIT {

    @Container
    @ServiceConnection
    static MySQLContainer<?> mysql = new MySQLContainer<>("mysql:8.0");

    @Autowired
    private TestRestTemplate restTemplate;

    @Test
    void getCities_returnsSeededCitiesFromDataSql() {
        ResponseEntity<City[]> response = restTemplate.getForEntity("/shipping/cities", City[].class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        City[] cities = response.getBody();
        assertThat(cities).isNotNull();
        // data.sql seeds exactly 25 cities.
        assertThat(cities).hasSize(25);

        assertThat(Arrays.stream(cities).map(City::getCity))
                .contains("New York", "London", "Tokyo", "Mumbai", "Sao Paulo");

        City newYork = Arrays.stream(cities)
                .filter(c -> "New York".equals(c.getCity()))
                .findFirst()
                .orElseThrow();
        assertThat(newYork.getCountryCode()).isEqualTo("US");
        // BigDecimal coordinates round-tripped through DECIMAL(10,7).
        assertThat(newYork.getLatitude().doubleValue()).isCloseTo(40.7128, within(1e-6));
        assertThat(newYork.getLongitude().doubleValue()).isCloseTo(-74.0060, within(1e-6));
    }

    @Test
    void calcShipping_seededCity_returnsComputedCostFromStoredCoordinates() {
        // AUTO_INCREMENT: first inserted row (New York) has id = 1.
        ResponseEntity<Map<String, Object>> response = restTemplate.exchange(
                "/shipping/calc?cityId=1",
                HttpMethod.GET,
                null,
                new ParameterizedTypeReference<Map<String, Object>>() {
                });

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        Map<String, Object> body = response.getBody();
        assertThat(body).isNotNull();

        assertThat(((Number) body.get("cityId")).longValue()).isEqualTo(1L);
        assertThat(body.get("city")).isEqualTo("New York");

        double shippingCost = ((Number) body.get("shippingCost")).doubleValue();
        // New York coordinates equal the warehouse coordinates -> haversine distance 0
        // -> cost clamps to the 5.00 minimum.
        assertThat(shippingCost).isGreaterThanOrEqualTo(5.00);
        assertThat(shippingCost).isEqualTo(5.00);
    }

    @Test
    void calcShipping_absentCity_returns500FromCityNotFound() {
        // No seeded city has id 99999 -> controller throws RuntimeException("City not found").
        ResponseEntity<String> response = restTemplate.getForEntity("/shipping/calc?cityId=99999", String.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
    }
}
