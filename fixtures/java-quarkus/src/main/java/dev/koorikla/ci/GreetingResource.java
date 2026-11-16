package dev.koorikla.ci;

import jakarta.ws.rs.DefaultValue;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;

@Path("/")
public class GreetingResource {

    static String greet(String name) {
        String n = name == null ? "" : name.strip();
        return "hello, " + (n.isEmpty() ? "world" : n);
    }

    @GET
    @Produces(MediaType.TEXT_PLAIN)
    public String hello(@QueryParam("name") @DefaultValue("") String name) {
        return greet(name);
    }
}
