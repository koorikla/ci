package dev.koorikla.ci;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;
import static org.junit.jupiter.api.Assertions.assertEquals;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

@QuarkusTest
class GreetingResourceTest {

    @Test
    void greets() {
        assertEquals("hello, world", GreetingResource.greet("  "));
        given().queryParam("name", "ci").when().get("/").then().statusCode(200).body(is("hello, ci"));
    }

    @Test
    void health() {
        given().when().get("/q/health/ready").then().statusCode(200);
    }
}
