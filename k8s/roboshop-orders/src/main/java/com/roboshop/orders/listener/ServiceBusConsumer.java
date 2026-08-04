package com.roboshop.orders.listener;

import com.azure.messaging.servicebus.ServiceBusClientBuilder;
import com.azure.messaging.servicebus.ServiceBusProcessorClient;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.Map;

/**
 * Consumes order events from the Azure Service Bus queue and hands each one to
 * {@link OrderListener}. Replaces the old RabbitMQ {@code @RabbitListener}.
 *
 * <p>If no connection string is configured (e.g. local runs / slice tests) the
 * processor is simply not started, so the app still boots.
 */
@Component
public class ServiceBusConsumer {

    private static final Logger logger = LoggerFactory.getLogger(ServiceBusConsumer.class);

    private final OrderListener orderListener;
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Value("${servicebus.connection-string:}")
    private String connectionString;

    @Value("${servicebus.queue:orders}")
    private String queue;

    private ServiceBusProcessorClient processor;

    public ServiceBusConsumer(OrderListener orderListener) {
        this.orderListener = orderListener;
    }

    @PostConstruct
    public void start() {
        if (connectionString == null || connectionString.isBlank()) {
            logger.warn("SERVICEBUS_CONNECTION_STRING not set; order consumer disabled");
            return;
        }

        processor = new ServiceBusClientBuilder()
                .connectionString(connectionString)
                .processor()
                .queueName(queue)
                .processMessage(context -> {
                    try {
                        String body = context.getMessage().getBody().toString();
                        Map<String, Object> event =
                                objectMapper.readValue(body, new TypeReference<Map<String, Object>>() {});
                        orderListener.handleOrderEvent(event);
                    } catch (Exception e) {
                        logger.error("Failed to process order message: {}", e.getMessage(), e);
                    }
                })
                .processError(context ->
                        logger.error("Service Bus error: {}", context.getException().getMessage()))
                .buildProcessorClient();

        processor.start();
        logger.info("Service Bus consumer started on queue: {}", queue);
    }

    @PreDestroy
    public void stop() {
        if (processor != null) {
            processor.close();
        }
    }
}
