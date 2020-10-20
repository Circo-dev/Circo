# ```@raw html
# <style>
#   .documenter-example-output { display:none !important }
#   .is-category-output { background-color: white  !important; color: black !important; border-color: lightsteelblue !important}
#   .is-category-output pre, .is-category-output code { background-color: white  !important; color: black !important; border-width: 0 !important}
#   .is-category-output .admonition-header { background-color: lightsteelblue !important }
# </style>
# ```
# # Tutorial
#
# Here you will learn how to start Circo, create actors, send messages and react to lifecycle
# events. We will program a distributed backend for Twitter clones from scratch.
#
# Don't worry, it is not complicated, just a simplified prototype! But it works,
# and it scales to any size...
#
# ### Architecture
#
# We build the system out of three building blocks: Posts, Feeds and Profiles.
# - `Post`s are simple structs with some text and the name of the author.
# - `Feed`s are actors holding a list of posts. When someone opens the frontend,
#    a new feed will be created for that session, and populated with recent posts.
#    While the feed is alive, it also receives pushed updates from its sources.
# - `Profile` actors can create posts and follow other profiles.
#
# ### Post
#
# We start with `Post`, which is a simple struct, as it has no behavior currently.
# We will store posts in feeds and profiles, and pass them as messages.

using Circo

struct Post
    authorname::String
    text::String
end

# ### Feed
#
# A `Feed` - our first - actor contains a growing list of posts from different authors.
#
#
# Actors in Circo are `mutable struct`s[^encapsulation], subtypes of `Actor`:
#
# [^encapsulation]: Actors encapsulate their state: They are to be accessed only through message passing.
#     This strict separation enables the scalability of the actor model, and I also believe
#     that it is very *natural*, meaning that it is aligned with how nature works.
#     It seems that shared state is not common in nature, which explains why systems that
#     provide shared state scale poorly.

mutable struct Feed <: Actor{Any}
    sources::Vector{Addr} # Post sources that this feed watches
    posts::Vector{Post}
    core::Any # A tiny boilerplate is needed
    Feed(sources) = new(sources, [])
end

# `core` is a required field to store system info, e.g. the id of the actor.
# You may sometimes use the information in `core`, but you should never access it directly,
# as its content is not fixed: Its type is assembled by the activated plugins.
#
# ---
#
# When the feed receives a `Post`, it just prints and stores it:

function Circo.onmessage(me::Feed, post::Post, service)
    println("Feed $(box(me)) received post: $post")
    push!(me.posts, post)
end

# By adding a method to `Circo.onmessage` we have defined how `Feed` actors *react*,
# when they receive a `Post` as a message.[^behaviors] The here unused `service` argument
# is for sending out messages, spawning actors or communicating with plugins.
#
# [^behaviors]: Unlike other actor systems, Circo does not complicate things with
#     replaceable actor behaviors. When we need an actor to change its behavior
#     dynamically, we can dispatch further in `onmessage`, or spawn another actor.
#     As always, performance was the main driver behind this design decision, but the API
#     is also definitely simpler. Actors are like objects in OOP, and objects does not have
#     replaceable behaviors.
#
# ---
#
# ### Try out what we have

feed = Feed([])

ctx = CircoContext()
s = Scheduler(ctx, [feed])
run!(s) # Start the scheduler in the background

#
# The `CircoContext` manages the configuration and helps building a tailored system:
# it loads the plugins, generates types, etc. The `Scheduler` then executes
# our actors in that context.
#
# ---
#
# The feed is scheduled and waiting for posts. We can send one from the outside:

send(s, feed, Post("Me", "My first post"))
sleep(1.0) # hide

# !!! output "Output"
#     ```
#     Feed 15794352489972218257 received post: Main.Post("Me", "My first post")
#     ```
#
# Great, the post arrived at the feed and got processed!
#
# ### Profile
#
# Now we will create a `Profile` actor that can create posts and follow other profiles.

mutable struct Profile <: Actor{Any}
    name::String
    posts::Vector{Post}
    following::Vector{Addr} # Adresses of the profiles we follow
    watchers::Vector{Addr} # Feeds to notify about our new posts
    core::Any
    Profile(name) = new(name, [], [], [])
end

#
# ---
#
# The `Profile` will start following another one if it receives the `Follow` message:

struct Follow
    whom::Addr
end

function Circo.onmessage(me::Profile, msg::Follow, service)
    println("$(me.name) ($(box(me))): Starting to follow $(box(msg.whom))")
    push!(me.following, msg.whom)
end

#
# ---
#
# Now we can create a few profiles and connect them. But first the running scheduler has to
# be paused and restarted for the new `onmessage` method to take effect.

pause!(s); run!(s)
alice = spawn(s, Profile("Alice"))
bela = spawn(s, Profile("Béla"))
cecile = spawn(s, Profile("Cécile"))

send(s, alice, Follow(bela))
send(s, alice, Follow(cecile))
send(s, bela, Follow(cecile))
sleep(1.0) # hide

# !!! output "Output"
#     ```
#     Alice (2519498415121108185): Starting to follow 3749599043616972853
#     Alice (2519498415121108185): Starting to follow 5769659525869689442
#     Bela (3749599043616972853): Starting to follow 5769659525869689442
#     ```
#
# ### Creating Posts, notifying watchers
#
# Profiles will create posts when they receive a `CreatePost` message:

struct CreatePost
    text::String
end

function Circo.onmessage(me::Profile, msg::CreatePost, service)
    post = Post(me.name, msg.text)
    println("Posting: $post")
    push!(me.posts, post)
    notify_watchers(me, post, service) # Send out the post to the feeds of our live followers (if any)
end

function notify_watchers(me::Profile, post, service)
    for watcher in me.watchers
        send(service, me, watcher, post)
    end
end

#
# ---
#
# Let our users create a few interesting posts:

pause!(s); run!(s)
send(s, alice, CreatePost("Through the Looking-Glass"))
send(s, bela, CreatePost("I lost my handkerchief"))
send(s, cecile, CreatePost("My first post"))
send(s, cecile, CreatePost("At the zoo"))
sleep(1.0) # hide

# !!! output "Output"
#     ```
#     Posting: Main.Post("Alice", "Through the Looking-Glass")
#     Posting: Main.Post("Bela", "I lost my handkerchief")
#     Posting: Main.Post("Cécile", "My first post")
#     Posting: Main.Post("Cécile", "At the zoo")
#     ```
#
# As there isn't any feed watching the profiles at the time, no notifications were sent out.
#
# ### Creating feeds
#
# So, time to create a live feed! The `CreateFeed` message asks a profile to create a feed that
# is sourced from the profiles that this one follows:

struct CreateFeed end
function Circo.onmessage(me::Profile, msg::CreateFeed, service)
    feed = spawn(service, Feed(copy(me.following)))
    println("Created Feed: $(feed)")
end

#
# ---
#
# When the feed actor is spawned, it starts watching the profiles by sending them an
# `AddWatcher` message:

struct AddWatcher
    watcher::Addr
end

function Circo.onspawn(me::Feed, service)
    for source in me.sources
        send(service, me, source, AddWatcher(addr(me)))
    end
end

#
# ---
#
# The profile reacts with immediately sending back its last 3 posts, and starting to send
# notifications about future posts:

function Circo.onmessage(me::Profile, msg::AddWatcher, service)
    for post in me.posts[max(end - 2, 1):end]
        send(service, me, msg.watcher, post)
    end
    push!(me.watchers, msg.watcher)
end

#
# ### Ta-da
#
# We are ready! We do not want to create the frontend, so let's just say that when
# someone opens the frontend app on their device, a Circo plugin or an external system
# will call:

pause!(s); run!(s) # hide
send(s, alice, CreateFeed())
sleep(1.0) # hide

# !!! output "Output"
#     ```
#     Created Feed: 192.168.193.99:24721/898192691fd68c14
#     Feed 9908361635395177492 received post: Main.Post("Cécile", "My first post")
#     Feed 9908361635395177492 received post: Main.Post("Cécile", "At the zoo")
#     Feed 9908361635395177492 received post: Main.Post("Béla", "I lost my handkerchief")
#     ```
#
# ---
#
# That's it! Just a final check that
# when Béla creates a new post, it will arrive on the feed of Alice:

send(s, bela, CreatePost("Have you ever seen a llama wearing pajamas?"))
sleep(1.0) # hide

# !!! output "Output"
#     ```
#     Posting: Main.Post("Bela", "Have you ever seen a llama wearing pajamas?")
#     Feed 9908361635395177492 received post: Main.Post("Bela", "Have you ever seen a llama wearing pajamas?")
#     ```
#
# ### Where to go
#
# Nothing more is needed to start coding in Circo. The best way to learn is to make something yourself.
#
# For closer-to-life Circo programs look into the [examples](https://github.com/Circo-dev/Circo/tree/master/examples)
# folder of the repo.
#
# Have fun!
