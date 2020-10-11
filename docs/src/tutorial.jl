# # Tutorial
#
# We will create a distributed engine for Twitter clones. Don't worry, it is not complicated,
# at least not in this unfinished prototype form. But it works, and it scales to any size!
#
# For simplicity, we store posts in simple structs (inside actors, but not actors themselves):

using Circo

struct Post
    authorname::String
    text::String
end

# A `Feed`, our first actor contains a growing list of posts from different authors.
# Our simplistic approach is that when someone opens the twitter clone, a new `Feed`
# will be created for that session, populated with recent posts. While the feed is alive,
# it also receives pushed updates from its sources.

mutable struct Feed <: AbstractActor{Any}
    posts::Vector{Post}
    sources::Vector{Addr} # Post sources that this feed watches
    core::Any # This small boilerplate is needed for every actor
    Feed() = new([], [])
    Feed(sources) = new(sources, [])
end

# When the feed receives a `Post`, it just prints and stores it:

function Circo.onmessage(me::Feed, post::Post, service)
    println("Feed $(box(me)) received post: $post")
    push!(me.posts, post)
end

# Now we can try out what we have:

feed = Feed()

ctx = CircoContext() # This is our connection to the Circo system
s = ActorScheduler(ctx, [feed])
@async s() # Start the scheduler in the background

send(s, feed, Post("Me", "My first post")) # Send a post from the outside to the feed
feed.posts

# Great, the post arrived at the feed! 
#
# Now we will create a `Profile` actor which can create posts and follow other profiles.

mutable struct Profile <: AbstractActor{Any}
    name::String
    posts::Vector{Post}
    following::Vector{Addr} # Adresses of the profiles we follow
    watchers::Vector{Addr} # Feeds to notify about our new posts
    core::Any
    Profile(name) = new(name, [], [], [])
end

# The `Profile` will start following another one if it receives the `Follow` message:

struct Follow
    whom::Addr
end

function Circo.onmessage(me::Profile, msg::Follow, service)
    println("$(me.name) ($(box(me))): Starting to follow $(box(msg.whom))")
    push!(me.following, msg.whom)
end

# Now we can create a few profiles and connect them:

alice = spawn(s, Profile("Alice"))
bela = spawn(s, Profile("Béla"))
cecile = spawn(s, Profile("Cécile"))
send(s, alice, Follow(bela))
send(s, alice, Follow(cecile))
send(s, bela, Follow(cecile))

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

# Let our users create a few interesting posts:

send(s, alice, CreatePost("Through the Looking-Glass"))
send(s, bela, CreatePost("I lost my handkerchief"))
send(s, cecile, CreatePost("My first post"))
send(s, cecile, CreatePost("At the zoo"))

# As there are no feed watching any of the profiles at the time, no notifications were sent out.
#
# Time to create a live feed! The `CreateFeed` message asks a profile to create a feed that
# is sourced from the profiles this one follows:

struct CreateFeed end
function Circo.onmessage(me::Profile, msg::CreateFeed, service)
    feed = spawn(service, Feed(copy(me.following)))
    println("Created Feed: $(feed)")
end

# When the feed is spawned, it starts watching the profiles by sending them an `AddWatcher` message.

struct AddWatcher
    watcher::Addr
end

function Circo.onschedule(me::Feed, service)
    for source in me.sources
        send(service, me, source, AddWatcher(addr(me)))
    end
end

# The profile reacts with immediately sending back its last 3 posts, and starting to send
# notifications about future posts:

function Circo.onmessage(me::Profile, msg::AddWatcher, service)
    for post in me.posts[max(end - 2, 1):end]
        send(service, me, msg.watcher, post)
    end
    push!(me.watchers, msg.watcher)
end
    
# At the end we can simulate the event that `Alice` opens the app like this:

send(s, alice, CreateFeed())

# When Béla creates a new post, it will arrive on the feed of Alice:

sleep(2.0)
send(s, bela, CreatePost("Have you ever seen a llama wearing pajamas?"))

# X
