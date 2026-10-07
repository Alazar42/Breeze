// example/scenes/scene_manager.zig — Scene navigation for Breeze Example.
const std = @import("std");
const breeze = @import("breeze");

pub const MainMenu = @import("main_menu.zig");
pub const Platformer = @import("platformer.zig");
pub const UIShowcase = @import("ui_showcase.zig");

pub fn goToMainMenu(tree: *breeze.SceneTree) !void {
    const scene = try MainMenu.createScene();
    tree.change_scene_to(scene);
}

pub fn goToPlatformer(tree: *breeze.SceneTree) !void {
    const scene = try Platformer.createScene();
    tree.change_scene_to(scene);
}

pub fn goToUIShowcase(tree: *breeze.SceneTree) !void {
    const scene = try UIShowcase.createScene();
    tree.change_scene_to(scene);
}
