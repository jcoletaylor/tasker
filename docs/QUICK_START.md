# Quick Start Guide: Your First Tasker Workflow

## Goal: Working Workflow in 15 Minutes

This guide will get you from zero to a working Tasker workflow in 15 minutes. You'll build a simple "Welcome Email" process that demonstrates core concepts like step dependencies, error handling, and result passing. This guide is done as an example - you don't have to actually have a User model or a welcome email process.

**🚀 New in Tasker 2.3.0**: This guide now benefits from our enterprise-grade registry system with thread-safe operations, structured logging with correlation IDs, and comprehensive validation - all working automatically behind the scenes for maximum reliability.

*Note*: This guide being an example, the step that gets a user from the database is unlikely to need to be retried - steps are generally best decomposed into units that need distinct idempotency and retryability guarantees.

## Prerequisites (2 minutes)

Before starting, ensure you have:
- **Rails application** (7.2+) with PostgreSQL
- **Ruby 3.2+**
- **Basic Rails knowledge** (models, controllers, ActiveJob)

## Installation & Setup (3 minutes)

### 1. Add Tasker to your Gemfile

```ruby
# Gemfile
source 'https://rubygems.pkg.github.com/jcoletaylor' do
  gem 'tasker', '~> 2.4.0'
end
```

### 2. Install and configure

```bash
bundle install
bundle exec rails tasker:install:migrations
bundle exec rails db:migrate
```

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount Tasker::Engine, at: '/tasker', as: 'tasker'
end
```

```bash
# Set up basic configuration
bundle exec rails tasker:setup
```

### 3. Create a simple User model (if you don't have one)

```bash
# Only if you don't already have a User model
rails generate model User name:string email:string
bundle exec rails db:migrate
```

## Your First Workflow: Welcome Email Process (8 minutes)

Let's create a workflow that:
1. **Validates** a user exists
2. **Generates** personalized welcome content
3. **Sends** the welcome email

### 1. Generate the workflow structure

```bash
rails generate tasker:task_handler WelcomeHandler --module_namespace WelcomeUser
```

This creates:
- `app/tasks/welcome_user/welcome_handler.rb` - Task handler class
- `config/tasker/tasks/welcome_user/welcome_handler.yaml` - Workflow configuration
- `spec/tasks/welcome_user/welcome_handler_spec.rb` - Test file

### 2. Configure the workflow (YAML)

Edit `config/tasker/tasks/welcome_user/welcome_handler.yaml`:

```yaml
---
name: welcome_user
module_namespace: WelcomeUser
task_handler_class: WelcomeHandler

schema:
  type: object
  required:
    - user_id
  properties:
    user_id:
      type: integer

step_templates:
  - name: validate_user
    description: Ensure user exists and is valid for welcome email
    handler_class: WelcomeUser::StepHandler::ValidateUserHandler

  - name: generate_content
    description: Generate personalized welcome email content
    depends_on_step: validate_user
    handler_class: WelcomeUser::StepHandler::GenerateContentHandler

  - name: send_email
    description: Send the welcome email to the user
    depends_on_step: generate_content
    handler_class: WelcomeUser::StepHandler::SendEmailHandler
    default_retryable: true
    default_retry_limit: 3
```

### 3. Create the task handler class

The main task handler from the generator, preset to read from the YAML configuration (`app/tasks/welcome_user/welcome_handler.rb`):

```ruby
# app/tasks/welcome_user/welcome_handler.rb
module WelcomeUser
  class WelcomeHandler < Tasker::ConfiguredTask
    # sample code from the generator
    # you can remove the sample code
    # and add your own code as outlined below
  end
end
```

### 4. Implement the step handlers

Create the directory structure:
```bash
mkdir -p app/tasks/welcome_user/step_handler
```

**Step 1: Validate User** (`app/tasks/welcome_user/step_handler/validate_user_handler.rb`):

```ruby
module WelcomeUser
  module StepHandler
    class ValidateUserHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        # note that the task.context is the same as the context passed in the task request
        # and that our schema defines user_id as required
        # task-request objects created from an API call will have a context that matches
        # the schema defined in the task handler and will be validated against the schema
        # before the task is executed
        user_id = task.context['user_id']

        user = User.find_by(id: user_id)
        raise "User not found with ID: #{user_id}" unless user
        raise "User email is missing" if user.email.blank?

        Rails.logger.info "Validated user: #{user.name} (#{user.email})"

        {
          user_id: user.id,
          user_name: user.name,
          user_email: user.email,
          validated: true
        }
      end
    end
  end
end
```

**Step 2: Generate Content** (`app/tasks/welcome_user/step_handler/generate_content_handler.rb`):

```ruby
module WelcomeUser
  module StepHandler
    class GenerateContentHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        # Get user data from previous step
        validate_step = sequence.find_step_by_name('validate_user')
        user_name = validate_step.results['user_name']
        user_email = validate_step.results['user_email']

        # Generate personalized content
        subject = "Welcome to our platform, #{user_name}!"
        body = generate_welcome_body(user_name)

        Rails.logger.info "Generated welcome content for #{user_name}"

        {
          subject: subject,
          body: body,
          to_email: user_email,
          to_name: user_name,
          generated_at: Time.current.iso8601
        }
      end

      private

      def generate_welcome_body(name)
        <<~BODY
          Hi #{name},

          Welcome to our platform! We're excited to have you on board.

          Here are some things you can do to get started:
          • Complete your profile
          • Explore our features
          • Join our community

          If you have any questions, don't hesitate to reach out.

          Best regards,
          The Team
        BODY
      end
    end
  end
end
```

**Step 3: Send Email** (`app/tasks/welcome_user/step_handler/send_email_handler.rb`):

```ruby
module WelcomeUser
  module StepHandler
    class SendEmailHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        # Get email content from previous step
        content_step = sequence.find_step_by_name('generate_content')
        email_data = content_step.results

        # In a real application, you'd use ActionMailer here
        # For this demo, we'll simulate sending
        success = send_welcome_email(email_data)

        if success
          Rails.logger.info "Welcome email sent to #{email_data['to_email']}"
          {
            email_sent: true,
            sent_to: email_data['to_email'],
            sent_at: Time.current.iso8601,
            subject: email_data['subject']
          }
        else
          raise "Failed to send email to #{email_data['to_email']}"
        end
      end

      private

      def send_welcome_email(email_data)
        # Simulate email sending (replace with real ActionMailer call)
        puts "\n" + "="*60
        puts "📧 WELCOME EMAIL SENT"
        puts "="*60
        puts "To: #{email_data['to_name']} <#{email_data['to_email']}>"
        puts "Subject: #{email_data['subject']}"
        puts "-" * 60
        puts email_data['body']
        puts "="*60 + "\n"

        # Simulate 90% success rate (for demo purposes)
        rand > 0.1
      end
    end
  end
end
```

## Testing Your Workflow (2 minutes)

### 1. Create a test user

```bash
rails console
```

```ruby
# In Rails console
user = User.create!(name: "Alice Smith", email: "alice@example.com")
puts "Created user: #{user.name} with ID: #{user.id}"
```

### 2. Run your workflow

```ruby
# Still in Rails console

# Create and execute the workflow
task_request = Tasker::Types::TaskRequest.new(
  name: 'welcome_user',
  namespace: 'notifications',    # NEW: Organize tasks by domain
  version: '1.0.0',             # NEW: Semantic versioning support
  context: { user_id: user.id }
)

# Handler lookup with namespace + version support
# Note: namespace and version are optional - they default to 'default' and '0.1.0'
handler = Tasker::HandlerFactory.instance.get(
  'welcome_user',
  namespace_name: 'notifications',  # Optional - defaults to 'default'
  version: '1.0.0'                 # Optional - defaults to '0.1.0'
)
task = handler.initialize_task!(task_request)

puts "Task created with ID: #{task.id}"
puts "Task status: #{task.state}"
```

### 3. Check the results

For this to have automatically processed, you need to have a job backend running
(Sidekiq, DelayedJob, etc.) and have the ActiveJob backend configured to use it.
In development, you may need to process jobs manually.

Immediately processing from the rails console (this is not recommended for production):

```ruby
# In Rails console
handler.handle(task)
```

```ruby
# Wait a moment for processing, then check status
task.reload
puts "Task status: #{task.state}"

# View the step results
task.workflow_steps.each do |step|
  puts "\nStep: #{step.name}"
  puts "Status: #{step.current_state}"
  puts "Results: #{step.results}"
end
```

If everything worked, you should see:
- ✅ Task status: `complete`
- ✅ All three steps with status: `complete`
- ✅ Welcome email output in your console
- ✅ Results passed between steps correctly

## Understanding What Happened

### Step Dependencies
1. **validate_user** ran first (no dependencies)
2. **generate_content** ran after validation completed (depends_on_step)
3. **send_email** ran after content generation completed

### Error Handling & Retries
- If step 1 fails (user not found), the workflow stops
- If step 3 fails (email sending), it will retry up to 3 times
- Each step's results are stored and available to dependent steps

### Data Flow
```
validate_user (gets user_id)
    ↓ (returns user data)
generate_content (uses user data)
    ↓ (returns email content)
send_email (uses email content)
    ↓ (returns delivery confirmation)
```

## What You've Learned

✅ **Created a multi-step workflow** with dependencies
✅ **Implemented step handlers** with business logic
✅ **Configured retry behavior** for unreliable operations
✅ **Passed data between steps** using results
✅ **Handled errors gracefully** with validation

## Using the REST API (Bonus: 5 minutes)

Tasker provides comprehensive REST API endpoints for programmatic workflow management. Here's how to interact with your workflow via API:

### 1. Discover Available Handlers

```bash
# List all namespaces
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     http://localhost:3000/tasker/handlers

# Explore handlers in notifications namespace
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     http://localhost:3000/tasker/handlers/notifications

# Get detailed handler information with dependency graph
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     http://localhost:3000/tasker/handlers/notifications/welcome_user?version=1.0.0
```

### 2. Create Tasks via API

```bash
# Create a welcome user task via REST API
curl -X POST -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "welcome_user",
       "namespace": "notifications",
       "version": "1.0.0",
       "context": {"user_id": 1}
     }' \
     http://localhost:3000/tasker/tasks
```

### 3. Monitor Task Progress

```bash
# Get task details with dependency analysis
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     http://localhost:3000/tasker/tasks/TASK_ID?include_dependencies=true
```

### 4. JavaScript Integration Example

```javascript
// Simple JavaScript client for workflow management
class TaskerClient {
  constructor(baseURL, token) {
    this.baseURL = baseURL;
    this.token = token;
  }

  async createWelcomeTask(userId) {
    const response = await fetch(`${this.baseURL}/tasks`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${this.token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        name: 'welcome_user',
        namespace: 'notifications',
        version: '1.0.0',
        context: { user_id: userId }
      })
    });

    return response.json();
  }

  async getTaskStatus(taskId) {
    const response = await fetch(`${this.baseURL}/tasks/${taskId}?include_dependencies=true`, {
      headers: {
        'Authorization': `Bearer ${this.token}`
      }
    });

    return response.json();
  }
}

// Usage
const tasker = new TaskerClient('http://localhost:3000/tasker', 'YOUR_JWT_TOKEN');
const task = await tasker.createWelcomeTask(1);
const status = await tasker.getTaskStatus(task.id);
```

The API response includes the dependency graph visualization:
```json
{
  "id": "welcome_user",
  "namespace": "notifications",
  "version": "1.0.0",
  "dependency_graph": {
    "nodes": ["validate_user", "generate_content", "send_email"],
    "edges": [
      {"from": "validate_user", "to": "generate_content"},
      {"from": "generate_content", "to": "send_email"}
    ],
    "execution_order": ["validate_user", "generate_content", "send_email"]
  }
}
```

For complete API documentation, see **[REST API Guide](REST_API.md)**.

## Next Steps

### 🚀 Build More Complex Workflows
- Add parallel steps (multiple steps depending on the same parent)
- Create diamond patterns (multiple paths that converge)
- Add API integration steps

### 🔧 Add Production Features
- **[REST API Guide](REST_API.md)** - Complete API documentation with handler discovery
- **[Authentication](AUTH.md)** - Secure your workflows
- **[Event Subscribers](EVENT_SYSTEM.md)** - Add monitoring and alerting
- **[Telemetry](TELEMETRY.md)** - OpenTelemetry spans for detailed tracing
- **[Metrics](METRICS.md)** - Native metrics collection for dashboards and alerting

### 📚 Explore Advanced Topics
- **[Developer Guide](DEVELOPER_GUIDE.md)** - Complete implementation guide with API integration
- **[Examples](../spec/examples/)** - Real-world workflow patterns and implementations
- **[System Overview](OVERVIEW.md)** - Architecture deep dive

## Troubleshooting

### Common Issues

**"Task handler not found"**
```bash
# Restart your Rails server to reload the new task handler
rails server
```

**"Step handler not found"**
- Check file paths match the class names exactly
- Ensure all files are saved and the server is restarted

**"Database errors"**
- Ensure migrations have run: `bundle exec rails db:migrate`
- Check PostgreSQL is running and accessible

**"Task stays in 'pending' state"**
- Check your ActiveJob backend is running (Sidekiq, DelayedJob, etc.)
- In development, you can process jobs manually if you want to see the results immediately (see above)

### Getting Help

- **[Troubleshooting Guide](TROUBLESHOOTING.md)** - Comprehensive issue resolution
- **[Developer Guide](DEVELOPER_GUIDE.md)** - Detailed implementation help
- Check the logs: `tail -f log/development.log`

---

🎉 **Congratulations!** You've built your first Tasker workflow. You now understand the core concepts and are ready to build more sophisticated workflows for your application.
