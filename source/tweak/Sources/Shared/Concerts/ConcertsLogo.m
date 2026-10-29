// The concerts logo (a ticket with a note), white on clear, 52 x 50 px for 3x. Drawn as a template so the
// glass card tints it like its text.
#import <UIKit/UIKit.h>
#import "Concerts.h"

UIImage *SGConcertsLogo(void) {
    static UIImage *logo;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *encoded =
    @"iVBORw0KGgoAAAANSUhEUgAAADQAAAAyCAYAAAATIfj2AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAA"
    @"DsMAAA7DAcdvqGQAAABmZVhJZklJKgAIAAAAAQBphwQAAQAAABoAAAAAAAAAAwAAkAcABAAAADAyMzABoAMAAQAAAAEAAAAF"
    @"oAQAAQAAAEQAAAAAAAAAAgABAAIABAAAAFI5OAACAAcABAAAADAxMDAAAAAAIvvHMbnUA7gAAAFsSURBVGhD7dLRisMwEEPR"
    @"/v9P72IWg3pxLDlOUtP1eexo5An09dq2bdu2a/wA58vjB7RwZyk8NsWej+BRM9j9CB5xJb51Cz56N74/heWfwJuGsGwFvDHC"
    @"khXwxhiLVsE7YyxaAW8ccknJSr7qY/6Ftz/zA9K3NRdjyRNG3tdshAWzkn43V5qNsGAEu1q4U7i50myEBQl29HC3cHOl2QgL"
    @"HO473C/cXGk2wgKH+w73CzdXmo2wwOE+McP9Udo1hEVHuKdaOf2tOtpRmjmNpS1pvpdxHTqfwuKWNN/LuA6dT2M5pdlexnXo"
    @"fAqLW9J8L+M6dD6FxS1pvpdxHTo/jaVHejs6q5gp3LzQzBAWOUe7+rvSzBnss1jQwp3KzYv3pj9urjQbYQExr0Yyys2VZiMs"
    @"IOaVy+lcJZlKsxEWEPMVc4WbV2mu0GyEBcR8xdyIkR7NRlhwZDTfM/K+ZmMsuVv6tuZOY+kn8KZt27amX6rg/cfw1YKzAAAA"
    @"AElFTkSuQmCC";
        NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
        UIImage *image = data ? [UIImage imageWithData:data scale:3] : nil;
        logo = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    });
    return logo;
}
