# TODO

* Create more rich examples of Tasker::TaskHandler implementations, especially with API integrations
* Create workflow diagrams for these examples
* Allow for task identity hash to be nil and create a default one from a guid
* Allow task identity hash to be a strategy pattern to allow others to bring their own
* Allow our backend jobs to be based off of [SolidQueue](https://github.com/rails/solid_queue) or [Sidekiq](https://github.com/sidekiq/sidekiq), and allow these to be configurable
* Provide examples of Tasker::TaskHandler that utilizes [Statesman](https://github.com/gocardless/statesman)
* Develop an example ReactJS frontend to view task status [using websockets](https://stephenmcbride.medium.com/how-to-use-action-cable-with-an-api-only-application-e1db58f1b7c6)
