package actor.starintel.starlang.runtime;

public final class JavaAbiSmoke {
    public static void main(String[] args) {
        StarRuntime runtime = StarRuntime.create();
        ActorHandler echo = (message, state, ignored) ->
            new ActorTransition(message, StateUpdate.Keep.INSTANCE);
        ActorDefinition definition = ActorDefinition.nativeActor(
            "java-echo",
            "star://local:localhost:java-echo",
            echo
        );
        ActorInstance actor = runtime.spawn(definition);
        PortableValue answer = runtime.ask(
            actor,
            new PortableValue.Text("ok"),
            1
        );
        if (!answer.equals(new PortableValue.Text("ok"))) {
            throw new AssertionError("Java ABI ask mismatch: " + answer);
        }
        System.out.println("runtime-jvm Java ABI smoke: PASS");
    }
}
