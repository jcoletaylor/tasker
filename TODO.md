# TODO

* I've had a chance to begin to build some GraphQL pieces for the application, and also build out RSwag for Swagger UI, but these need to be updated before they are really ready. [The current release](https://github.com/jcoletaylor/tasker/releases/tag/v0.1.1) is really just a pre-release while I get the rest of the bugs worked out, but the Gem is viable as-is.
* It would also be good to expose some configuration options to the Tasker Engine, or allow it to inherit scopes / roles / policies for auth from the app where the engine is installed, so that the routes (default: `/tasker`) can be secured.
* I plan to migrate to [jsonapi-rails](http://jsonapi-rb.org/) for API JSON serialization - right now it's using `ActiveModel::Serializer` implementations which are not as fast or quite as expressive as I'd like.
* I will probably also want to build a few more closer-to-real-world examples of `Tasker::TaskHandler` implementations, so that it's more obvious how to build complex logic with the framework.
