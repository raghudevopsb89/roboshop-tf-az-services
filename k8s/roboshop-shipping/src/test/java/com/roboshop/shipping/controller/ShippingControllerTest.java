package com.roboshop.shipping.controller;

import com.roboshop.shipping.model.City;
import com.roboshop.shipping.repository.CityRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Web slice tests for {@link ShippingController}. The JPA repository is mocked with
 * {@link MockBean} so no real datasource (MySQL / schema.sql / data.sql) is needed.
 */
@WebMvcTest(ShippingController.class)
class ShippingControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private CityRepository cityRepository;

    private City newYork() {
        City city = new City();
        city.setId(1L);
        city.setCountryCode("US");
        city.setCity("New York");
        city.setRegion("New York");
        // Same coordinates as the warehouse -> haversine distance 0 -> minimum cost.
        city.setLatitude(new BigDecimal("40.7128000"));
        city.setLongitude(new BigDecimal("-74.0060000"));
        return city;
    }

    @Test
    void health_returnsOkJson() throws Exception {
        mockMvc.perform(get("/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("OK"))
                .andExpect(jsonPath("$.service").value("shipping"));
    }

    @Test
    void getCities_returnsList() throws Exception {
        when(cityRepository.findAll()).thenReturn(List.of(newYork()));

        mockMvc.perform(get("/shipping/cities"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", org.hamcrest.Matchers.hasSize(1)))
                .andExpect(jsonPath("$[0].id").value(1))
                .andExpect(jsonPath("$[0].city").value("New York"))
                .andExpect(jsonPath("$[0].countryCode").value("US"));
    }

    @Test
    void calculateShipping_knownCity_returnsExpectedMap() throws Exception {
        when(cityRepository.findById(1L)).thenReturn(Optional.of(newYork()));

        // Warehouse == city coordinates -> distance 0 -> cost clamped to the 5.00 minimum.
        mockMvc.perform(get("/shipping/calc").param("cityId", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.cityId").value(1))
                .andExpect(jsonPath("$.city").value("New York"))
                .andExpect(jsonPath("$.shippingCost").value(5.00));
    }

    @Test
    void calculateShipping_unknownCity_throws() {
        when(cityRepository.findById(999L)).thenReturn(Optional.empty());

        // The controller throws an unhandled RuntimeException, which MockMvc propagates.
        assertThatThrownBy(() ->
                mockMvc.perform(get("/shipping/calc").param("cityId", "999")))
                .hasRootCauseInstanceOf(RuntimeException.class)
                .hasRootCauseMessage("City not found");
    }
}
