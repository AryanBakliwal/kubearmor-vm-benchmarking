# import base64
# from locust import HttpUser, task, between
# from random import choice

# # Sample product IDs from the standard Sock Shop catalog
# ITEM_IDS = [
#     "03fef6ac-1896-4ce8-bd69-b798f85c6e0b",
#     "3395a43e-2d88-40de-b95f-e00e1502085b",
#     "837ab141-399e-4c1f-9abc-bace40296bac",
#     "a0a4f044-b040-410d-8ead-4de0446aec7e"
# ]

# class WebSiteUser(HttpUser):
#     # Simulate a user taking between 1 to 5 seconds to click the next link
#     wait_time = between(1.0, 5.0)

#     def on_start(self):
#         """
#         Executed when a simulated user starts.
#         Registers a dummy user so checkout doesn't fail.
#         """
#         self.client.post("/register", json={
#             "username": "testuser",
#             "password": "password",
#             "email": "test@example.com"
#         })
        
#         # Set basic auth header for future requests requiring login
#         auth = base64.b64encode(b"testuser:password").decode("ascii")
#         self.client.headers.update({"Authorization": f"Basic {auth}"})

#     @task(5)
#     def index_page(self):
#         """Simulate loading the home page (Hits Frontend)"""
#         self.client.get("/")

#     @task(4)
#     def browse_category(self):
#         """Simulate browsing a category (Hits Frontend -> Catalogue)"""
#         self.client.get("/category.html")

#     @task(3)
#     def view_item(self):
#         """Simulate viewing a specific item (Hits Frontend -> Catalogue)"""
#         item_id = choice(ITEM_IDS)
#         self.client.get(f"/detail.html?id={item_id}")

#     @task(2)
#     def add_to_cart(self):
#         """Simulate adding an item to the cart (Hits Frontend -> Cart)"""
#         item_id = choice(ITEM_IDS)
#         self.client.post("/cart", json={"id": item_id, "quantity": 1})

#     @task(1)
#     def checkout(self):
#         """Simulate the checkout process (Hits Orders, Payment, Shipping)"""
#         # First, view the cart
#         self.client.get("/basket.html")
        
#         # Proceed to checkout
#         self.client.post("/orders")

#     @task(1)
#     def view_profile(self):
#         """Simulate viewing user profile (Hits User service)"""
#         self.client.get("/customer-orders.html")

from locust import HttpUser, task, between
import random

class VotingUser(HttpUser):
    # Short wait time to generate heavy load
    wait_time = between(0.5, 2.0)

    @task(3)
    def load_front_page(self):
        """Simulate a user loading the voting page"""
        self.client.get("/")

    @task(2)
    def cast_vote(self):
        """Simulate a user casting a vote (Triggers Web -> Redis -> .NET Worker -> Postgres)"""
        self.client.post("/", data={"vote": random.choice(["a", "b"])})